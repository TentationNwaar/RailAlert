import SwiftUI

/// Détail d'un trajet : train surveillé, trains suivants, réglages.
struct TripDetailView: View {
    @EnvironmentObject private var model: TripsModel
    @Environment(\.dismiss) private var dismiss
    let tripID: UUID

    @State private var showEditor = false
    @State private var testSent = false

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
    }

    private func content(_ trip: Trip) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                TripCardView(trip: trip,
                             report: report,
                             isLoading: model.loading.contains(trip.id),
                             error: model.errors[trip.id],
                             networkAlerts: [])

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

                if let report, !report.upcoming.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(t("Prochains départs")).font(.headline)
                        ForEach(report.upcoming) { connection in
                            ConnectionRow(connection: connection, threshold: trip.delayThreshold)
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
