import Foundation

/// Une observation du train surveillé, enregistrée peu avant son départ.
struct TripObservation: Codable, Hashable {
    let connectionID: String
    let plannedDeparture: Date
    let delayMinutes: Int?
    let cancelled: Bool
    let observedAt: Date
}

/// Statistiques de ponctualité d'un trajet sur une période.
struct PunctualityStats {
    let days: Int
    let observed: Int
    let onTime: Int
    let delayed: Int
    let cancelled: Int
    /// Retard moyen des trains en retard (minutes).
    let averageDelay: Double?

    var onTimeRate: Double { observed == 0 ? 0 : Double(onTime) / Double(observed) }
}

/// Historique de ponctualité, gardé 60 jours dans l'App Group.
///
/// Une observation est enregistrée à chaque vérification faite entre 45 min avant et 45 min après
/// le départ prévu ; pour un même train, on garde la plus récente (la plus proche de la réalité).
/// Les statistiques ne portent donc que sur les jours où l'app a pu vérifier le trajet.
final class TripHistoryStore {
    static let shared = TripHistoryStore()

    private let defaults = UserDefaults(suiteName: AppConfig.appGroupID) ?? .standard
    private let key = "history.v1"
    private let keepDays = 60

    private func loadAll() -> [UUID: [TripObservation]] {
        guard let data = defaults.data(forKey: key),
              let all = try? JSONDecoder().decode([UUID: [TripObservation]].self, from: data)
        else { return [:] }
        return all
    }

    private func saveAll(_ all: [UUID: [TripObservation]]) {
        if let data = try? JSONEncoder().encode(all) { defaults.set(data, forKey: key) }
    }

    func observations(for tripID: UUID) -> [TripObservation] {
        loadAll()[tripID] ?? []
    }

    /// Enregistre l'état du train surveillé s'il part bientôt (ou vient de partir).
    func record(_ connection: ConnectionInfo, tripID: UUID, now: Date = .now) {
        guard abs(connection.plannedDeparture.timeIntervalSince(now)) <= 45 * 60 else { return }
        var all = loadAll()
        var list = all[tripID] ?? []
        list.removeAll { $0.connectionID == connection.id }
        list.append(TripObservation(connectionID: connection.id,
                                    plannedDeparture: connection.plannedDeparture,
                                    delayMinutes: connection.departureDelay,
                                    cancelled: connection.isCancelled,
                                    observedAt: now))
        let limit = now.addingTimeInterval(-Double(keepDays) * 24 * 3600)
        list = list.filter { $0.plannedDeparture >= limit }.sorted { $0.plannedDeparture < $1.plannedDeparture }
        all[tripID] = list
        saveAll(all)
    }

    func removeHistory(for tripID: UUID) {
        var all = loadAll()
        all[tripID] = nil
        saveAll(all)
    }

    /// Statistiques des `days` derniers jours, avec le seuil de retard du trajet.
    func stats(for trip: Trip, days: Int = 30, now: Date = .now) -> PunctualityStats {
        let since = now.addingTimeInterval(-Double(days) * 24 * 3600)
        let list = observations(for: trip.id).filter { $0.plannedDeparture >= since && $0.plannedDeparture <= now }
        let cancelled = list.filter(\.cancelled)
        let delayed = list.filter { !$0.cancelled && ($0.delayMinutes ?? 0) >= trip.delayThreshold }
        let onTime = list.count - cancelled.count - delayed.count
        let delays = delayed.compactMap(\.delayMinutes)
        return PunctualityStats(
            days: days,
            observed: list.count,
            onTime: onTime,
            delayed: delayed.count,
            cancelled: cancelled.count,
            averageDelay: delays.isEmpty ? nil : Double(delays.reduce(0, +)) / Double(delays.count)
        )
    }
}
