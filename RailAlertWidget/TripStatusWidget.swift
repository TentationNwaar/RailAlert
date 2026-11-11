import WidgetKit
import SwiftUI

// MARK: - Point d'entrée du widget

@main
struct RedAlertWidgetBundle: WidgetBundle {
    var body: some Widget {
        TripStatusWidget()
        TripLiveActivity()
    }
}

/// Widget "Mon trajet" : écran verrouillé (au-dessus / sous l'heure) et écran d'accueil.
struct TripStatusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: AppConfig.widgetKind, provider: TripProvider()) { entry in
            TripWidgetView(entry: entry)
        }
        .configurationDisplayName(t("Mon trajet"))
        .description(t("Retards, suppressions, perturbations et travaux sur ton prochain trajet."))
        .supportedFamilies([
            .accessoryRectangular, .accessoryInline, .accessoryCircular,
            .systemSmall, .systemMedium
        ])
    }
}

// MARK: - Données affichées

struct TripEntry: TimelineEntry {
    let date: Date
    let report: TripReport?
    let message: String?
    /// Perturbations et travaux sur le parcours (calculés par l'app, lus dans l'App Group).
    var networkAlerts: [TripNetworkAlert] = []

    static var sample: TripEntry {
        let from = Station(id: "8501300", name: "Montreux", latitude: 46.4359, longitude: 6.9104)
        let to = Station(id: "8501120", name: "Lausanne", latitude: 46.5168, longitude: 6.6291)
        let trip = Trip(from: from, to: to, usualHour: 7, usualMinute: 23)
        let dep = Calendar.current.date(bySettingHour: 7, minute: 23, second: 0, of: .now) ?? .now
        let focus = ConnectionInfo(plannedDeparture: dep, plannedArrival: dep.addingTimeInterval(23 * 60),
                                   departureDelay: 4, arrivalDelay: 4, isCancelled: false,
                                   line: "IR 95", track: "1", terminal: "Genève-Aéroport",
                                   transfers: 0, notices: [])
        return TripEntry(date: .now,
                         report: TripReport(trip: trip, focus: focus, upcoming: [focus], fetchedAt: .now),
                         message: nil)
    }
}

// MARK: - Fournisseur : quand et quoi afficher

struct TripProvider: TimelineProvider {
    func placeholder(in context: Context) -> TripEntry { .sample }

    func getSnapshot(in context: Context, completion: @escaping (TripEntry) -> Void) {
        if context.isPreview {
            completion(.sample)
            return
        }
        Task { completion(await makeEntry()) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TripEntry>) -> Void) {
        Task {
            let entry = await makeEntry()
            // iOS limite le nombre de rafraîchissements d'un widget (environ 40 à 70 par jour).
            // On rafraîchit plus souvent quand le trajet approche.
            let minutes = isDepartureSoon(entry) ? 10.0 : 30.0
            let next = Date().addingTimeInterval(minutes * 60)
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }

    private func makeEntry() async -> TripEntry {
        let trips = Premium.monitoredTrips(TripStore.shared.loadTrips())
        guard let trip = TripChecker.mostRelevantTrip(in: trips) else {
            return TripEntry(date: .now, report: nil, message: t("Ajoute un trajet dans Rail Alert"))
        }
        let networkAlerts = TripStore.shared.loadNetworkAlerts()[trip.id] ?? []
        do {
            let report = try await TripChecker.report(for: trip)
            return TripEntry(date: .now, report: report, message: nil, networkAlerts: networkAlerts)
        } catch {
            // Hors ligne : on affiche le dernier état connu.
            let cached = TripStore.shared.loadReports()[trip.id]
            return TripEntry(date: .now, report: cached, message: cached == nil ? t("Horaire indisponible") : nil,
                             networkAlerts: networkAlerts)
        }
    }

    private func isDepartureSoon(_ entry: TripEntry) -> Bool {
        guard let departure = entry.report?.focus?.expectedDeparture else { return false }
        return departure.timeIntervalSinceNow < 2 * 3600
    }
}

// MARK: - Affichage

struct TripWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TripEntry

    private var report: TripReport? { entry.report }
    private var focus: ConnectionInfo? { report?.focus }
    /// Perturbation ou chantier sur le parcours (la plus grave en premier).
    private var networkAlert: TripNetworkAlert? { entry.networkAlerts.first }

    /// Le train lui-même a-t-il un problème (retard au-dessus du seuil, suppression) ?
    private var trainHasProblem: Bool {
        let s = report?.severity ?? .unknown
        return s == .warning || s == .critical
    }

    /// Gravité affichée : celle du train, sinon celle d'une perturbation / de travaux sur le parcours.
    private var severity: TripReport.Severity {
        if trainHasProblem { return report?.severity ?? .unknown }
        if let networkAlert { return networkAlert.isInterruption ? .critical : .warning }
        return report?.severity ?? .unknown
    }

    private var symbol: String {
        if !trainHasProblem, networkAlert != nil { return "exclamationmark.triangle.fill" }
        return Formatting.symbol(for: severity)
    }

    private var stateText: String {
        if !trainHasProblem, let networkAlert { return networkAlert.label }
        return focus.map { Formatting.stateText($0.state) } ?? "—"
    }

    private var shortStateText: String {
        if !trainHasProblem, let networkAlert { return networkAlert.isConstruction ? t("Travaux") : t("Alerte") }
        return focus.map { Formatting.shortStateText($0.state) } ?? "—"
    }

    private var shortTitle: String {
        guard let trip = report?.trip else { return "Rail Alert" }
        return "\(trip.from.name) → \(trip.to.name)"
    }

    var body: some View {
        Group {
            switch family {
            case .accessoryInline: inline
            case .accessoryCircular: circular
            case .accessoryRectangular: rectangular
            case .systemMedium: medium
            default: small
            }
        }
        // Toucher le widget ouvre le trajet dans l'app.
        .widgetURL(report.map { AppConfig.tripURL($0.trip.id) })
        .containerBackground(for: .widget) {
            LinearGradient(colors: [Color(red: 0.17, green: 0.22, blue: 0.32),
                                    Color(red: 0.07, green: 0.09, blue: 0.15)],
                           startPoint: .top, endPoint: .bottom)
        }
    }

    // Écran verrouillé, une ligne au-dessus de l'heure.
    @ViewBuilder
    private var inline: some View {
        if let focus {
            Label("\(Formatting.time(focus.plannedDeparture)) \(shortStateText) · \(report?.trip.to.name ?? "")",
                  systemImage: symbol)
        } else {
            Label(entry.message ?? "Rail Alert", systemImage: "tram")
        }
    }

    // Écran verrouillé, petit rond.
    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: symbol).font(.body.weight(.bold))
                Text(shortStateText)
                    .font(.system(size: 12, weight: .bold))
                    .minimumScaleFactor(0.6)
            }
            .widgetAccentable()
        }
    }

    // Écran verrouillé, rectangle sous l'heure : le format principal.
    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                Text(stateText).fontWeight(.bold)
            }
            .font(.headline)
            .widgetAccentable()

            Text(shortTitle)
                .font(.caption)
                .lineLimit(1)

            if !trainHasProblem, let networkAlert {
                // Ex. "07:23 · Vevey – Puidoux interrompu"
                Text(alertLine(networkAlert))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else if let focus {
                Text(detailLine(focus))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else if let message = entry.message {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(shortTitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(2)
            Spacer(minLength: 0)
            if let focus {
                Text(Formatting.time(focus.plannedDeparture))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .strikethrough(focus.isCancelled)
                statusPill
                if let line = focus.line {
                    Text(line + (focus.track.map { t(" · voie %@", $0) } ?? ""))
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))
                }
            } else {
                Text(entry.message ?? t("Aucun train")).font(.footnote).foregroundStyle(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var medium: some View {
        HStack(spacing: 16) {
            small
            if let report {
                VStack(alignment: .leading, spacing: 6) {
                    Text(t("Ensuite")).font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.7))
                    ForEach(Array(report.upcoming.dropFirst().prefix(3))) { connection in
                        HStack {
                            Text(Formatting.time(connection.plannedDeparture))
                                .strikethrough(connection.isCancelled)
                            Spacer()
                            Text(Formatting.shortStateText(connection.state))
                                .foregroundStyle(connection.isCancelled ? Color(red: 0.94, green: 0.23, blue: 0.21) : Color.white.opacity(0.8))
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                    }
                    Spacer(minLength: 0)
                    if let notice = networkAlert?.title ?? report.focus?.notices.first {
                        Text(notice).font(.caption2).foregroundStyle(.yellow).lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    private var statusPill: some View {
        Label(stateText, systemImage: symbol)
            .font(.caption.weight(.bold))
            .foregroundStyle(severity == .unknown ? Color.white : Color.black)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(pillColor, in: Capsule())
    }

    private var pillColor: Color {
        switch severity {
        case .ok: return Color(red: 0.25, green: 0.80, blue: 0.45)
        case .warning: return Color(red: 1.00, green: 0.78, blue: 0.10)
        case .critical: return Color(red: 0.94, green: 0.23, blue: 0.21)
        case .unknown: return .gray
        }
    }

    /// "07:23 · Le trafic ferroviaire est interrompu entre Vevey et Puidoux."
    private func alertLine(_ alert: TripNetworkAlert) -> String {
        guard let focus else { return alert.title }
        return Formatting.time(focus.plannedDeparture) + " · " + alert.title
    }

    /// "07:23 IR 95 · voie 1" ou "Supprimé · prochain 07:53"
    private func detailLine(_ focus: ConnectionInfo) -> String {
        var parts = [Formatting.time(focus.plannedDeparture)]
        if focus.isCancelled, let alt = report?.nextAlternative {
            parts.append(t("prochain %@", Formatting.time(alt.expectedDeparture)))
        } else {
            if let line = focus.line { parts.append(line) }
            if let track = focus.track { parts.append(t("voie %@", track)) }
        }
        return parts.joined(separator: " · ")
    }
}

#Preview(as: .accessoryRectangular) {
    TripStatusWidget()
} timeline: {
    TripEntry.sample
}
