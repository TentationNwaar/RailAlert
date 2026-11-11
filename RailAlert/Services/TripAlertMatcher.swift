import Foundation

/// Garde en mémoire la dernière liste d'alertes du réseau, pour que la carte, les trajets
/// et la vérification en arrière-plan n'aient pas à retélécharger le flux (≈ 1 Mo) chacun de leur côté.
actor AlertCache {
    static let shared = AlertCache()

    private var last: DisruptionService.Result?
    private var fetchedAt: Date?
    /// Langue des textes en cache : si l'utilisateur change de langue, on recharge.
    private var language: AppLanguage?

    /// Renvoie les alertes, en les rechargeant si elles datent de plus de `maxAge` secondes.
    func result(maxAge: TimeInterval = 240) async throws -> DisruptionService.Result {
        let currentLanguage = AppLanguage.current
        if let last, let fetchedAt, language == currentLanguage, Date().timeIntervalSince(fetchedAt) < maxAge {
            return last
        }
        let fresh = try await DisruptionService.shared.fetchAlerts()
        last = fresh
        fetchedAt = .now
        language = currentLanguage
        return fresh
    }
}

/// Trouve, pour chaque trajet, les perturbations et travaux qui le concernent.
///
/// Règles (vérifiées le 30.09.2026 sur le flux réel, trajet Montreux → Berne) :
/// 1. Lieu : le train roule directement entre deux gares touchées par l'alerte
///    (deux arrêts consécutifs du trajet, ex. Vevey puis Chexbres-Village pour des travaux Vevey – Puidoux).
///    Une alerte qui ne cite qu'une gare compte seulement si son titre nomme cette gare
///    (ex. « restreint en gare de Fribourg »).
/// 2. Moment : une des plages horaires de l'alerte recouvre l'horaire du train surveillé
///    (des travaux de nuit ne concernent pas un trajet de 7 h du matin).
enum TripAlertMatcher {
    static func match(trip: Trip, report: TripReport?, alerts: [RailAlert]) -> [TripNetworkAlert] {
        // Train de référence : celui de l'heure habituelle, sinon le prochain.
        guard let connection = report?.focus ?? report?.upcoming.first else { return [] }

        let route = connection.stopIDs.compactMap(StationNumber.short)
        // Si l'horaire n'a pas donné les arrêts, on se contente du départ et de l'arrivée.
        let routeNumbers = route.isEmpty
            ? [trip.from.id, trip.to.id].compactMap(StationNumber.short)
            : route
        guard !routeNumbers.isEmpty else { return [] }
        let routeSet = Set(routeNumbers)

        // Horaire du train, retard compris, avec 10 minutes de marge.
        let departure = connection.expectedDeparture.addingTimeInterval(-10 * 60)
        let arrival = connection.plannedArrival
            .addingTimeInterval(TimeInterval((connection.arrivalDelay ?? connection.departureDelay ?? 0) * 60) + 10 * 60)
        let journey = DateInterval(start: departure, end: max(arrival, departure))

        return alerts.compactMap { alert -> TripNetworkAlert? in
            guard alert.severity != .info else { return nil }
            let alertNumbers = Set(alert.places.compactMap { StationNumber.short($0.id) })
            guard !alertNumbers.isEmpty else { return nil }

            let touchesRoute: Bool
            if alert.places.count == 1, let place = alert.places.first {
                // Alerte sur une seule gare : la gare doit être sur le trajet et nommée dans le titre.
                touchesRoute = alertNumbers.isSubset(of: routeSet)
                    && alert.section.localizedCaseInsensitiveContains(place.name)
            } else {
                // Deux arrêts consécutifs du trajet sont touchés par l'alerte.
                touchesRoute = zip(routeNumbers, routeNumbers.dropFirst()).contains { pair in
                    alertNumbers.contains(pair.0) && alertNumbers.contains(pair.1)
                }
            }
            guard touchesRoute, alert.overlaps(journey) else { return nil }

            // Plage à afficher : celle qui recouvre le trajet.
            let ranges = alert.periods.isEmpty ? [alert.window].compactMap { $0 } : alert.periods
            let range = ranges.first { $0.start <= journey.end && $0.end >= journey.start }

            return TripNetworkAlert(
                id: alert.id,
                title: alert.section,
                details: alert.details,
                isConstruction: alert.kind == .construction,
                isInterruption: alert.severity == .interrupted,
                start: range.map(\.start).flatMap { $0 == .distantPast ? nil : $0 },
                end: range.map(\.end).flatMap { $0 == .distantFuture ? nil : $0 }
            )
        }
        .sorted { lhs, rhs in
            if lhs.isInterruption != rhs.isInterruption { return lhs.isInterruption }
            return (lhs.start ?? .distantPast) < (rhs.start ?? .distantPast)
        }
    }

    /// Calcule et enregistre les alertes de tous les trajets (lues ensuite par le widget).
    static func matchAll(trips: [Trip], reports: [UUID: TripReport], alerts: [RailAlert]) -> [UUID: [TripNetworkAlert]] {
        var result: [UUID: [TripNetworkAlert]] = [:]
        for trip in trips {
            result[trip.id] = match(trip: trip, report: reports[trip.id], alerts: alerts)
        }
        TripStore.shared.saveNetworkAlerts(result)
        return result
    }
}
