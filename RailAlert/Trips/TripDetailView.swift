import SwiftUI

/// Détail d'un trajet : train surveillé, trains suivants, réglages.
struct TripDetailView: View {
    @EnvironmentObject private var model: TripsModel
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = StoreManager.shared
    let tripID: UUID

    @State private var showEditor = false
    @State private var testSent = false
    @State private var boardStation: Station?
    /// Départ touché (pastille ou liste) : on affiche son trajet complet.
    @State private var selectedConnection: ConnectionInfo?
    @State private var isLive = false
    @State private var liveError: String?

    private var trip: Trip? { model.trips.first { $0.id == tripID } }
    private var report: TripReport? { model.reports[tripID] }

    var body: some View {
        Group {
            if let trip {
                content(trip)
            } else {
                ContentUnavailableView(t("Trajet supprimé"), systemImage: "trash")
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(trip?.title ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if trip != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(t("Modifier")) { showEditor = true }
                }
            }
        }
    }

    private func content(_ trip: Trip) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                TripCardView(trip: trip,
                             report: report,
                             isLoading: model.loading.contains(trip.id),
                             error: model.errors[trip.id],
                             networkAlerts: [],
                             alternativesUnlocked: store.isPremium,
                             onSelectConnection: { selectedConnection = $0 })

                if let alerts = model.networkAlerts[trip.id], !alerts.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(t("Perturbations et travaux sur le parcours")).font(.headline)
                        ForEach(alerts) { alert in
                            NetworkAlertRow(alert: alert, showDetails: true)
                            if alert.id != alerts.last?.id { Divider() }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardStyle()
                }

                // Trajet complet avec les correspondances.
                if let focus = report?.focus, !(focus.legs ?? []).isEmpty {
                    JourneyView(connection: focus)
                }

                // Messages officiels sur le train surveillé (perturbation, travaux, bus de remplacement...).
                if let messages = report?.focus?.messages, !messages.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(t("Messages sur ton train")).font(.headline).accessibilityAddTraits(.isHeader)
                        ForEach(messages) { message in
                            ServiceMessageRow(message: message)
                            if message.id != messages.last?.id { Divider() }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardStyle()
                }

                // Suivi en direct (Live Activity) sur l'écran verrouillé et dans la Dynamic Island.
                if !store.isPremium {
                    PremiumLockedCard(title: t("Suivi en direct"),
                                      text: t("Sur l'écran verrouillé et dans la Dynamic Island."))
                } else {
                    VStack(spacing: 6) {
                        Button {
                            Task { await toggleLive(trip) }
                        } label: {
                            Label(isLive ? t("Arrêter le suivi en direct") : t("Suivre en direct sur l'écran verrouillé"),
                                  systemImage: isLive ? "stop.circle.fill" : "dot.radiowaves.left.and.right")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(isLive ? Color.gray : Theme.red)
                        if let liveError {
                            Text(liveError).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                if store.isPremium {
                    PunctualityCard(trip: trip)
                } else {
                    PremiumLockedCard(title: t("Ponctualité sur 30 jours"),
                                      text: t("L'historique de ton train sur 30 jours."))
                }

                // Tableaux des départs des deux gares.
                HStack(spacing: 10) {
                    ForEach([trip.from, trip.to]) { station in
                        Button {
                            boardStation = station
                        } label: {
                            VStack(spacing: 2) {
                                Image(systemName: "list.bullet.rectangle")
                                Text(t("Départs de %@", station.name))
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let report, !report.upcoming.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(t("Prochains départs")).font(.headline)
                        ForEach(report.upcoming) { connection in
                            Button { selectedConnection = connection } label: {
                                ConnectionRow(connection: connection, threshold: trip.delayThreshold)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint(t("Affiche le trajet complet de ce départ"))
                            if connection.id != report.upcoming.last?.id { Divider() }
                        }
                        Text(t("Mis à jour à %@", Formatting.time(report.fetchedAt)))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardStyle()
                }

                VStack(spacing: 12) {
                    Button {
                        Task { await model.refresh(trip) }
                    } label: {
                        Label(t("Actualiser"), systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        Task {
                            await TripMonitor.sendTest(for: trip)
                            testSent = true
                        }
                    } label: {
                        Label(t("Tester une notification (dans 5 s)"), systemImage: "bell.badge")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    if testSent {
                        Text(t("Verrouille ton iPhone maintenant pour voir la notification."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        showEditor = true
                    } label: {
                        Label(t("Modifier le trajet"), systemImage: "pencil")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button(role: .destructive) {
                        model.delete(trip)
                        dismiss()
                    } label: {
                        Label(t("Supprimer"), systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(16)
        }
        .refreshable { await model.refresh(trip) }
        .sheet(isPresented: $showEditor) {
            TripEditorView(trip: trip) { model.update($0) }
        }
        .sheet(item: $boardStation) { station in
            StationBoardView(station: station)
        }
        .sheet(item: $selectedConnection) { connection in
            ConnectionDetailSheet(connection: connection,
                                  isMonitored: connection.id == report?.focus?.id) {
                // « Surveiller ce départ » : l'heure habituelle du trajet devient celle de ce départ.
                var updated = trip
                let calendar = AppConfig.swissCalendar
                updated.usualHour = calendar.component(.hour, from: connection.plannedDeparture)
                updated.usualMinute = calendar.component(.minute, from: connection.plannedDeparture)
                model.update(updated)
            }
            .presentationDetents([.medium, .large])
        }
        .onAppear { isLive = LiveActivityManager.isRunning(tripID: trip.id) }
    }

    private func toggleLive(_ trip: Trip) async {
        if isLive {
            await LiveActivityManager.stop(tripID: trip.id)
            isLive = false
            return
        }
        guard let report else {
            liveError = t("Horaire indisponible")
            return
        }
        let started = LiveActivityManager.start(trip: trip, report: report,
                                                networkAlerts: model.networkAlerts[trip.id] ?? [])
        isLive = started
        liveError = started ? nil : t("Suivi en direct indisponible. Vérifie qu'il est autorisé dans Réglages > Rail Alert.")
    }
}

/// Ponctualité du train surveillé sur les 30 derniers jours.
private struct PunctualityCard: View {
    let trip: Trip

    var body: some View {
        let stats = TripHistoryStore.shared.stats(for: trip)
        VStack(alignment: .leading, spacing: 10) {
            Text(t("Ponctualité sur 30 jours")).font(.headline)
            if stats.observed == 0 {
                Text(t("Pas encore de données. Rail Alert enregistre l'état de ton train à chaque vérification faite peu avant le départ."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(Int((stats.onTimeRate * 100).rounded())) %")
                        .font(.system(.largeTitle, design: .rounded).weight(.bold))
                        .foregroundStyle(stats.onTimeRate >= 0.9 ? Theme.green : (stats.onTimeRate >= 0.7 ? Theme.yellow : Theme.red))
                    Text(t("à l'heure")).font(.subheadline).foregroundStyle(.secondary)
                }
                // Barre : à l'heure / en retard / supprimé.
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        bar(Theme.green, Double(stats.onTime), stats, geo.size.width)
                        bar(Theme.yellow, Double(stats.delayed), stats, geo.size.width)
                        bar(Theme.red, Double(stats.cancelled), stats, geo.size.width)
                    }
                }
                .frame(height: 8)
                .clipShape(Capsule())
                .accessibilityHidden(true)

                HStack(spacing: 14) {
                    legend(Theme.green, t("%ld à l'heure", stats.onTime))
                    legend(Theme.yellow, t("%ld en retard", stats.delayed))
                    legend(Theme.red, t("%ld supprimé(s)", stats.cancelled))
                }
                if let average = stats.averageDelay {
                    Text(t("Retard moyen quand il y a du retard : %ld min", Int(average.rounded())))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(t("Basé sur %ld vérification(s) faite(s) par l'app. Retard compté à partir de %ld min.", stats.observed, trip.delayThreshold))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
        .accessibilityElement(children: .combine)
    }

    private func bar(_ color: Color, _ value: Double, _ stats: PunctualityStats, _ width: CGFloat) -> some View {
        Rectangle()
            .fill(color)
            .frame(width: stats.observed == 0 ? 0 : max(0, width * value / Double(stats.observed) - 2))
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).font(.caption)
        }
    }
}

/// Ligne d'un départ dans la liste détaillée.
private struct ConnectionRow: View {
    let connection: ConnectionInfo
    let threshold: Int

    private var severity: TripReport.Severity {
        if connection.isCancelled { return .critical }
        if connection.isProblem(threshold: threshold) { return .warning }
        if case .unknown = connection.state { return .unknown }
        return .ok
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(Formatting.time(connection.plannedDeparture))
                    .font(.title3.weight(.bold))
                    .strikethrough(connection.isCancelled, color: Theme.red)
                Text("→ \(Formatting.time(connection.plannedArrival))")
                    .foregroundStyle(.secondary)
                Spacer()
                StatusBadge(severity: severity, text: Formatting.stateText(connection.state))
            }
            HStack(spacing: 8) {
                if let line = connection.line { Text(line).fontWeight(.semibold) }
                if let terminal = connection.terminal { Text(t("direction %@", terminal)) }
                if let track = connection.track { Text(t("· voie %@", track)) }
                if connection.transfers > 0 {
                    Text(connection.transfers > 1 ? t("· %ld changements", connection.transfers) : t("· 1 changement"))
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)

            ForEach(connection.notices, id: \.self) { notice in
                Label(notice, systemImage: "exclamationmark.bubble.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.yellow)
            }
        }
    }
}

/// Un message officiel : résumé, puis détails à déplier.
private struct ServiceMessageRow: View {
    let message: ServiceMessage
    @State private var expanded = false

    private var color: Color { message.affectsService ? Theme.yellow : Theme.accent }
    private var symbol: String {
        message.affectsService ? "exclamationmark.bubble.fill" : "figure.roll"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text(message.summary).font(.subheadline.weight(.semibold))
            } icon: {
                Image(systemName: symbol).foregroundStyle(color)
            }
            if !message.details.isEmpty {
                if expanded {
                    Text(message.details)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button(expanded ? t("Moins de détails") : t("Plus de détails")) {
                    withAnimation(Motion.adaptive(.easeInOut(duration: 0.2))) { expanded.toggle() }
                }
                .font(.caption.weight(.semibold))
                .minimumTapTarget()
            }
        }
    }
}
