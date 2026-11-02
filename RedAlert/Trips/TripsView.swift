import SwiftUI

/// Onglet "Mes trajets" : liste des trajets habituels avec leur état en temps réel.
struct TripsView: View {
    @EnvironmentObject private var model: TripsModel
    @EnvironmentObject private var tutorial: TutorialController
    @ObservedObject private var store = StoreManager.shared
    @ObservedObject private var router = AppRouter.shared
    @State private var showEditor = false
    @State private var showPaywall = false
    /// Pile de navigation : permet d'ouvrir un trajet depuis une notification ou le widget.
    @State private var path: [UUID] = []
    @State private var savedCount = 0
    /// Trajet en cours de modification (gares, heure, jours et seuil déjà remplis).
    @State private var editingTrip: Trip?
    /// Trajet retour prérempli (gares inversées, mêmes jours et réglages).
    @State private var returnTrip: Trip?

    /// Trajet retour : gares inversées, mêmes jours, mêmes alertes ; l'heure est à choisir.
    private func makeReturnTrip(from trip: Trip) {
        guard store.isPremium || model.trips.count < Premium.freeTripLimit else {
            showPaywall = true
            return
        }
        var back = Trip(from: trip.to, to: trip.from)
        back.weekdays = trip.weekdays
        back.notificationsEnabled = trip.notificationsEnabled
        back.delayThreshold = trip.delayThreshold
        back.usualHour = trip.usualHour
        back.usualMinute = trip.usualMinute
        returnTrip = back
    }

    /// Version gratuite : 1 trajet. Au-delà, on propose Red Alert+.
    private func addTrip() {
        if store.isPremium || model.trips.count < Premium.freeTripLimit {
            showEditor = true
        } else {
            showPaywall = true
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if model.trips.isEmpty {
                    emptyState
                } else {
                    tripList
                }
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(t("Mes trajets"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { addTrip() } label: {
                        Image(systemName: "plus.circle.fill").font(.title3)
                    }
                    .accessibilityLabel(t("Ajouter un trajet"))
                }
            }
            .sheet(isPresented: $showEditor) {
                TripEditorView {
                    model.add($0)
                    savedCount += 1
                }
            }
            .sheet(item: $editingTrip) { trip in
                TripEditorView(trip: trip) {
                    model.update($0)
                    savedCount += 1
                }
            }
            .sheet(item: $returnTrip) { trip in
                TripEditorView(trip: trip, title: t("Trajet retour")) {
                    model.add($0)
                    savedCount += 1
                }
            }
            .sensoryFeedback(.success, trigger: savedCount)
            // Notification, widget ou suivi en direct touché : on ouvre le trajet.
            .onChange(of: router.pendingTripID, initial: true) { _, id in
                guard let id else { return }
                router.pendingTripID = nil
                guard model.trips.contains(where: { $0.id == id }) else { return }
                path = [id]
            }
            .sheet(isPresented: $showPaywall) { PaywallView() }
            .navigationDestination(for: UUID.self) { id in
                TripDetailView(tripID: id)
            }
            // Bouton "Ajouter mon premier trajet" du tutoriel.
            .onChange(of: tutorial.requestAddTrip) { _, requested in
                guard requested else { return }
                tutorial.requestAddTrip = false
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 350_000_000)
                    addTrip()
                }
            }
        }
    }

    private var tripList: some View {
        List {
            ForEach(model.trips) { trip in
                let paused = !store.isPremium && Premium.isPaused(trip, in: model.trips)
                // Toute la carte est un bouton (utilisable aussi avec VoiceOver et le contrôle de sélection).
                Button {
                    if paused { showPaywall = true } else { path.append(trip.id) }
                } label: {
                    if paused {
                        // Trajet en pause (version gratuite) : toucher la carte propose Red Alert+.
                        TripCardView(trip: trip, report: nil, isLoading: false, error: nil, isPaused: true)
                    } else {
                        TripCardView(trip: trip,
                                     report: model.reports[trip.id],
                                     isLoading: model.loading.contains(trip.id),
                                     error: model.errors[trip.id],
                                     networkAlerts: model.networkAlerts[trip.id] ?? [],
                                     alternativesUnlocked: store.isPremium)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityHint(paused ? t("Ouvre Red Alert+") : t("Ouvre le détail du trajet"))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                .swipeActions {
                    Button(role: .destructive) { model.delete(trip) } label: {
                        Label(t("Supprimer"), systemImage: "trash")
                    }
                    Button { editingTrip = trip } label: {
                        Label(t("Modifier"), systemImage: "pencil")
                    }
                    .tint(Theme.accent)
                }
                // Appui long : modifier, créer le retour, supprimer.
                .contextMenu {
                    Button { editingTrip = trip } label: {
                        Label(t("Modifier"), systemImage: "pencil")
                    }
                    Button { makeReturnTrip(from: trip) } label: {
                        Label(t("Créer le trajet retour"), systemImage: "arrow.uturn.left")
                    }
                    Button(role: .destructive) { model.delete(trip) } label: {
                        Label(t("Supprimer"), systemImage: "trash")
                    }
                }
            }
            .onMove { model.move(from: $0, to: $1) }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable { await model.refreshAll(force: true) }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(t("Aucun trajet"), systemImage: "tram")
        } description: {
            Text(t("Ajoute un trajet que tu fais souvent. Red Alert te préviendra en cas de retard, de suppression, de perturbation ou de travaux sur ton parcours, même sur l’écran verrouillé."))
        } actions: {
            Button(t("Ajouter un trajet")) { addTrip() }
                .buttonStyle(.borderedProminent)
        }
    }
}

// MARK: - Carte d'un trajet

struct TripCardView: View {
    let trip: Trip
    let report: TripReport?
    let isLoading: Bool
    let error: String?
    /// Perturbations et travaux qui touchent ce trajet.
    var networkAlerts: [TripNetworkAlert] = []
    /// Nombre maximal d'alertes réseau affichées (la page de détail les montre toutes).
    var maxNetworkAlerts = 2
    /// Alternatives visibles (Red Alert+). Sinon, un encart indique qu'une alternative existe.
    var alternativesUnlocked = true
    /// Trajet non surveillé (version gratuite, au-delà du premier trajet).
    var isPaused = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Ligne 1 : trajet + état
            HStack(alignment: .firstTextBaseline) {
                Text(trip.title)
                    .font(.headline)
                    .lineLimit(2)
                Spacer(minLength: 8)
                if isLoading && report == nil {
                    ProgressView().controlSize(.small)
                } else if let report {
                    StatusBadge(severity: report.severity,
                                text: report.focus.map { Formatting.stateText($0.state) } ?? t("Aucun train"))
                }
            }

            // Ligne 2 : heure habituelle
            Text(trip.usualTimeText.map { t("Habituellement %@ · %@", $0, trip.weekdaysText) } ?? t("Prochain départ"))
                .font(.caption)
                .foregroundStyle(.secondary)

            if isPaused {
                Label(t("En pause : la version gratuite surveille 1 trajet. Touche pour découvrir Red Alert+."),
                      systemImage: "pause.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            // Ligne 3 : train surveillé
            if let focus = report?.focus {
                HStack(alignment: .lastTextBaseline, spacing: 10) {
                    Text(Formatting.time(focus.plannedDeparture))
                        .font(.system(.largeTitle, design: .rounded).weight(.bold))
                        .strikethrough(focus.isCancelled, color: Theme.red)
                        .minimumScaleFactor(0.7)
                    if let delay = focus.departureDelay, delay != 0, !focus.isCancelled {
                        Text("→ \(Formatting.time(focus.expectedDeparture))")
                            .accessibilityLabel(t("Départ estimé à %@", Formatting.time(focus.expectedDeparture)))
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Theme.yellow)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        if let line = focus.line {
                            Text(line)
                                .font(.caption.weight(.bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Theme.red, in: RoundedRectangle(cornerRadius: 5))
                        }
                        if let occupancy = focus.occupancy {
                            OccupancyView(occupancy: occupancy, compact: true)
                        }
                    }
                    // Voie de départ, bien visible (jaune quand elle a changé).
                    if let track = focus.track, !focus.isCancelled {
                        TrackBadge(track: track, plannedTrack: focus.plannedTrack, changed: focus.trackChanged,
                                   mode: focus.legs?.first?.mode ?? "rail")
                    }
                }
            }

            // Alternative quand le train surveillé a un problème.
            if let report, let alternative = report.bestAlternative ?? (hasInterruption ? report.nextAlternative : nil) {
                Label(alternativesUnlocked ? t("Alternative : %@", Formatting.alternativeText(alternative))
                                           : t("Un autre train est disponible · Red Alert+"),
                      systemImage: alternativesUnlocked ? "arrow.triangle.branch" : "lock.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Theme.accent.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
            }

            // Correspondance menacée par un retard.
            if !isPaused, let risk = report?.focus?.transferRisks.first {
                Label(risk.isMissed
                      ? t("Correspondance compromise à %@", risk.station)
                      : t("Correspondance serrée à %@ : %ld min", risk.station, max(risk.marginMinutes, 0)),
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(risk.isMissed ? Theme.redText : Theme.yellow)
            }

            // Ligne 4 : trains suivants
            if let report, report.upcoming.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(report.upcoming.dropFirst().prefix(4)) { connection in
                            ConnectionChip(connection: connection, threshold: trip.delayThreshold)
                        }
                    }
                }
            }

            // Message de perturbation
            if let notice = report?.focus?.notices.first {
                Label(notice, systemImage: "exclamationmark.bubble.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.yellow)
                    .lineLimit(3)
            }

            // Perturbations et travaux sur le parcours
            if !networkAlerts.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(networkAlerts.prefix(maxNetworkAlerts)) { alert in
                        NetworkAlertRow(alert: alert, showDetails: false)
                    }
                    if networkAlerts.count > maxNetworkAlerts {
                        Text(t("+ %ld autre(s)", networkAlerts.count - maxNetworkAlerts))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let error {
                Text(error).font(.caption).foregroundStyle(Theme.redText)
            }
        }
        .cardStyle()
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .strokeBorder(borderColor, lineWidth: networkAlerts.isEmpty ? 0 : 1.5)
        )
        .opacity(isPaused ? 0.55 : 1)
    }

    private var hasInterruption: Bool { networkAlerts.contains(where: \.isInterruption) }

    private var borderColor: Color {
        networkAlerts.contains(where: \.isInterruption) ? Theme.red.opacity(0.8) : Theme.yellow.opacity(0.7)
    }
}

/// Ligne "Travaux · interruption — Vevey – Puidoux — ce soir 20:30 → 04:00".
struct NetworkAlertRow: View {
    let alert: TripNetworkAlert
    var showDetails: Bool

    private var color: Color { alert.isInterruption ? Theme.red : Theme.yellow }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Image(systemName: "triangle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(color)
                Image(systemName: alert.isConstruction ? "hammer.fill" : "exclamationmark")
                    .font(.system(size: alert.isConstruction ? 8 : 10, weight: .black))
                    .foregroundStyle(.black)
                    .offset(y: 2)
            }
            .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "\(alert.label) · \(alert.whenText)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(color)
                Text(alert.title)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(showDetails ? nil : 2)
                if showDetails && !alert.details.isEmpty {
                    Text(alert.details)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Pastille colorée : "À l'heure", "+4 min", "Supprimé".
struct StatusBadge: View {
    let severity: TripReport.Severity
    let text: String

    var body: some View {
        Label(text, systemImage: Formatting.symbol(for: severity))
            .font(.caption.weight(.bold))
            .foregroundStyle(severity == .unknown ? Color.white : Color.black)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Theme.color(for: severity), in: Capsule())
    }
}

/// Petite pastille pour un train suivant.
struct ConnectionChip: View {
    let connection: ConnectionInfo
    let threshold: Int

    private var color: Color {
        if connection.isCancelled { return Theme.red }
        if connection.isProblem(threshold: threshold) { return Theme.yellow }
        return Theme.green
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(Formatting.time(connection.plannedDeparture))
                .strikethrough(connection.isCancelled)
            if case .delayed(let minutes) = connection.state {
                Text("+\(minutes)").foregroundStyle(Theme.yellow)
            } else if case .early(let minutes) = connection.state {
                Text("−\(minutes)").foregroundStyle(Theme.yellow)
            }
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.white.opacity(0.08), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Formatting.time(connection.plannedDeparture)), \(Formatting.stateText(connection.state))")
    }
}

/// Voie de départ en grand : « Voie 7 », sur fond jaune avec « au lieu de 5 » quand elle a changé.
struct TrackBadge: View {
    let track: String
    let plannedTrack: String?
    let changed: Bool
    var mode = "rail"

    var body: some View {
        VStack(spacing: 0) {
            Text(mode == "rail" ? t("Voie") : t("Quai"))
                .font(.caption2.weight(.semibold))
            Text(track)
                .font(.system(.title, design: .rounded).weight(.heavy))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            if changed, let plannedTrack {
                Text(t("au lieu de %@", plannedTrack))
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .foregroundStyle(changed ? Color.black : Color.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(minWidth: 58)
        .background(changed ? Theme.yellow : Color.white.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(changed
            ? (plannedTrack.map { t("Changement de voie : voie %@ au lieu de %@", track, $0) } ?? t("Changement de voie : voie %@", track))
            : Formatting.platformText(track, mode: mode))
    }
}

/// Affiche "Voie 4" en gris, ou en jaune avec une icône si la voie a changé.
struct TrackLabelStyle: LabelStyle {
    let changed: Bool

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            if changed { configuration.icon }
            configuration.title
        }
        .font(.caption.weight(changed ? .bold : .regular))
        .foregroundStyle(changed ? Theme.yellow : Color.secondary)
    }
}
