import Foundation

/// Vérifie l'état d'un trajet : retrouve le train habituel et ses alternatives.
enum TripChecker {
    static func report(for trip: Trip, now: Date = .now) async throws -> TripReport {
        // 1. Quel départ surveiller ?
        //    On garde l'heure habituelle "valable" jusqu'à 30 min après,
        //    pour suivre un train en retard qui n'est pas encore parti.
        let anchor = trip.nextOccurrence(after: now.addingTimeInterval(-30 * 60))

        // 2. On interroge l'horaire un peu avant ce départ.
        let queryStart = anchor.map { $0.addingTimeInterval(-10 * 60) } ?? now
        let all = try await TimetableService.shared.connections(
            from: trip.from, to: trip.to, at: queryStart, count: 6
        )

        // 3. On retire les trains déjà partis.
        let stillRelevant = all.filter { $0.expectedDeparture >= now.addingTimeInterval(-60) }

        // 4. Train surveillé : le plus proche de l'heure habituelle (±15 min), sinon le prochain.
        var focus: ConnectionInfo?
        if let anchor {
            focus = stillRelevant
                .filter { abs($0.plannedDeparture.timeIntervalSince(anchor)) <= 15 * 60 }
                .min { abs($0.plannedDeparture.timeIntervalSince(anchor)) < abs($1.plannedDeparture.timeIntervalSince(anchor)) }
        }
        if focus == nil { focus = stillRelevant.first }

        let upcoming = stillRelevant.filter { $0.plannedDeparture >= (focus?.plannedDeparture ?? now) }

        let report = TripReport(trip: trip, focus: focus, upcoming: upcoming, fetchedAt: now)
        TripStore.shared.saveReport(report)
        // Historique de ponctualité (seulement si le train part bientôt ou vient de partir).
        if let focus { TripHistoryStore.shared.record(focus, tripID: trip.id, now: now) }
        return report
    }

    /// Choisit le trajet à mettre en avant (widget) : celui dont l'heure habituelle arrive en premier.
    static func mostRelevantTrip(in trips: [Trip], now: Date = .now) -> Trip? {
        let timed = trips.compactMap { trip -> (Trip, Date)? in
            guard let next = trip.nextOccurrence(after: now.addingTimeInterval(-30 * 60)) else { return nil }
            return (trip, next)
        }
        if let soonest = timed.min(by: { $0.1 < $1.1 }) { return soonest.0 }
        return trips.first
    }
}
