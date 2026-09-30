import Foundation
import WidgetKit

/// Liste des trajets de l'utilisateur et leur dernier état connu.
@MainActor
final class TripsModel: ObservableObject {
    @Published private(set) var trips: [Trip]
    @Published private(set) var reports: [UUID: TripReport]
    @Published private(set) var loading: Set<UUID> = []
    @Published private(set) var errors: [UUID: String] = [:]
    /// Perturbations et travaux qui concernent chaque trajet.
    @Published private(set) var networkAlerts: [UUID: [TripNetworkAlert]]

    init() {
        trips = TripStore.shared.loadTrips()
        reports = TripStore.shared.loadReports()
        networkAlerts = TripStore.shared.loadNetworkAlerts()
    }

    // MARK: Modification

    func add(_ trip: Trip) {
        trips.append(trip)
        persist()
        Task { await refresh(trip) }
        Task { _ = await TripMonitor.requestAuthorization() }
    }

    func update(_ trip: Trip) {
        guard let index = trips.firstIndex(where: { $0.id == trip.id }) else { return }
        trips[index] = trip
        persist()
        Task { await refresh(trip) }
    }

    func delete(_ trip: Trip) {
        trips.removeAll { $0.id == trip.id }
        reports[trip.id] = nil
        networkAlerts[trip.id] = nil
        TripStore.shared.saveNetworkAlerts(networkAlerts)
        persist()
    }

    func move(from source: IndexSet, to destination: Int) {
        trips.move(fromOffsets: source, toOffset: destination)
        persist()
    }

    private func persist() {
        TripStore.shared.saveTrips(trips)
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: Rafraîchissement

    func refreshAll() async {
        await withTaskGroup(of: Void.self) { group in
            for trip in trips {
                group.addTask { await self.refreshSchedule(trip) }
            }
        }
        await updateNetworkAlerts()
        WidgetCenter.shared.reloadAllTimelines()
    }

    func refresh(_ trip: Trip) async {
        await refreshSchedule(trip)
        await updateNetworkAlerts()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Horaire en temps réel du trajet (retard, suppression, gares desservies).
    private func refreshSchedule(_ trip: Trip) async {
        loading.insert(trip.id)
        defer { loading.remove(trip.id) }
        do {
            let report = try await TripChecker.report(for: trip)
            reports[trip.id] = report
            errors[trip.id] = nil
        } catch {
            errors[trip.id] = t("Horaire indisponible (%@)", error.localizedDescription)
        }
    }

    /// Croise les perturbations et travaux du réseau avec les gares et l'horaire de chaque trajet.
    private func updateNetworkAlerts() async {
        guard let result = try? await AlertCache.shared.result() else { return }
        networkAlerts = TripAlertMatcher.matchAll(trips: trips, reports: reports, alerts: result.alerts)
    }
}
