import SwiftUI

/// Onglet "Mes trajets" : liste des trajets habituels avec leur état en temps réel.
struct TripsView: View {
    @EnvironmentObject private var model: TripsModel
    @EnvironmentObject private var tutorial: TutorialController
    @State private var showEditor = false

    var body: some View {
        NavigationStack {
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
                    Button { showEditor = true } label: {
                        Image(systemName: "plus.circle.fill").font(.title3)
                    }
                }
            }
            .sheet(isPresented: $showEditor) {
                TripEditorView { model.add($0) }
            }
            .navigationDestination(for: UUID.self) { id in
                TripDetailView(tripID: id)
            }
            // Bouton "Ajouter mon premier trajet" du tutoriel.
            .onChange(of: tutorial.requestAddTrip) { _, requested in
                guard requested else { return }
                tutorial.requestAddTrip = false
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 350_000_000)
                    showEditor = true
                }
            }
        }
    }

    private var tripList: some View {
        List {
            ForEach(model.trips) { trip in
                ZStack {
                    // Lien invisible : toute la carte est cliquable, sans chevron.
                    NavigationLink(value: trip.id) { EmptyView() }.opacity(0)
                    TripCardView(trip: trip,
                                 report: model.reports[trip.id],
                                 isLoading: model.loading.contains(trip.id),
                                 error: model.errors[trip.id],
                                 networkAlerts: model.networkAlerts[trip.id] ?? [])
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                .swipeActions {
                    Button(role: .destructive) { model.delete(trip) } label: {
                        Label(t("Supprimer"), systemImage: "trash")
                    }
                }
            }
            .onMove { model.move(from: $0, to: $1) }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable { await model.refreshAll() }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(t("Aucun trajet"), systemImage: "tram")
        } description: {
            Text(t("Ajoute un trajet que tu fais souvent. Red Alert te préviendra en cas de retard, de suppression, de perturbation ou de travaux sur ton parcours, même sur l’écran verrouillé."))
        } actions: {
            Button(t("Ajouter un trajet")) { showEditor = true }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Ligne 1 : trajet + état
            HStack(alignment: .firstTextBaseline) {
                Text(trip.title)
                    .font(.headline)
                    .lineLimit(1)
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

            // Ligne 3 : train surveillé
            if let focus = report?.focus {
                HStack(alignment: .lastTextBaseline, spacing: 10) {
                    Text(Formatting.time(focus.plannedDeparture))
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .strikethrough(focus.isCancelled, color: Theme.red)
                    if let delay = focus.departureDelay, delay > 0, !focus.isCancelled {
                        Text("→ \(Formatting.time(focus.expectedDeparture))")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Theme.yellow)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        if let line = focus.line {
                            Text(line)
                                .font(.caption.weight(.bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Theme.red, in: RoundedRectangle(cornerRadius: 5))
                        }
                        if let track = focus.track {
                            Text(t("Voie %@", track)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
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
                Text(error).font(.caption).foregroundStyle(Theme.red)
            }
        }
        .cardStyle()
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .strokeBorder(borderColor, lineWidth: networkAlerts.isEmpty ? 0 : 1.5)
        )
    }

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
            }
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.white.opacity(0.08), in: Capsule())
    }
}
