import Foundation
import CoreLocation

// MARK: - Gare

/// Une gare ou un arrêt, identifié par son numéro officiel (ex. 8501120 = Lausanne).
struct Station: Codable, Hashable, Identifiable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

// MARK: - Trajet habituel

/// Un trajet que l'utilisateur fait souvent (ex. Montreux → Lausanne à 07:23 en semaine).
struct Trip: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var from: Station
    var to: Station

    /// Heure de départ habituelle. `nil` = on surveille simplement le prochain train.
    var usualHour: Int?
    var usualMinute: Int?

    /// Jours actifs, convention `Calendar` : 1 = dimanche, 2 = lundi, ..., 7 = samedi.
    var weekdays: Set<Int> = [2, 3, 4, 5, 6]

    /// Envoyer des notifications pour ce trajet.
    var notificationsEnabled: Bool = true

    /// Retard minimal (en minutes) à partir duquel on considère qu'il y a un problème.
    var delayThreshold: Int = 3

    var title: String { "\(from.name) → \(to.name)" }

    var hasUsualTime: Bool { usualHour != nil && usualMinute != nil }

    var usualTimeText: String? {
        guard let h = usualHour, let m = usualMinute else { return nil }
        return String(format: "%02d:%02d", h, m)
    }

    var weekdaysText: String {
        if weekdays.count == 7 || weekdays.isEmpty { return t("Tous les jours") }
        if weekdays == [2, 3, 4, 5, 6] { return t("En semaine") }
        if weekdays == [1, 7] { return t("Le week-end") }
        // Noms courts des jours dans la langue choisie ("lun." / "Mo." / "lun" / "Mon").
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = AppLanguage.current.locale
        let names = calendar.shortStandaloneWeekdaySymbols // index 0 = dimanche
        let order = [2, 3, 4, 5, 6, 7, 1]
        return order.filter { weekdays.contains($0) }.map { names[$0 - 1] }.joined(separator: ", ")
    }

    /// Prochaine occurrence de l'heure habituelle strictement après `date`, sur un jour actif.
    func nextOccurrence(after date: Date) -> Date? {
        guard let h = usualHour, let m = usualMinute else { return nil }
        let calendar = AppConfig.swissCalendar
        let startOfDay = calendar.startOfDay(for: date)
        for offset in 0..<8 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: startOfDay),
                  let candidate = calendar.date(bySettingHour: h, minute: m, second: 0, of: day)
            else { continue }
            let weekday = calendar.component(.weekday, from: candidate)
            let dayIsActive = weekdays.isEmpty || weekdays.contains(weekday)
            if dayIsActive && candidate > date { return candidate }
        }
        return nil
    }

    /// Le trajet est-il "d'actualité" ? (de 2 h avant à 30 min après l'heure habituelle)
    /// Sans heure habituelle, il est toujours d'actualité.
    func isInMonitoringWindow(_ now: Date) -> Bool {
        guard hasUsualTime else { return true }
        guard let next = nextOccurrence(after: now.addingTimeInterval(-30 * 60)) else { return false }
        return next.timeIntervalSince(now) <= 2 * 3600
    }
}

// MARK: - Correspondance (un train précis)

/// État d'un départ.
enum DepartureState: Hashable {
    case onTime
    case delayed(minutes: Int)
    case cancelled
    case unknown
}

/// Une correspondance renvoyée par l'horaire (search.ch).
struct ConnectionInfo: Codable, Hashable, Identifiable {
    let plannedDeparture: Date
    let plannedArrival: Date
    /// Retard au départ en minutes (`nil` = pas d'information temps réel).
    let departureDelay: Int?
    let arrivalDelay: Int?
    let isCancelled: Bool
    /// Ligne, ex. "IR 95".
    let line: String?
    let track: String?
    let terminal: String?
    let transfers: Int
    /// Messages de perturbation liés à cette correspondance.
    let notices: [String]
    /// Numéros des gares desservies (ex. "8501300" = Montreux), dans l'ordre.
    var stopIDs: [String] = []

    var id: String { "\(line ?? "-")-\(Int(plannedDeparture.timeIntervalSince1970))" }

    var state: DepartureState {
        if isCancelled { return .cancelled }
        guard let delay = departureDelay else { return .unknown }
        return delay > 0 ? .delayed(minutes: delay) : .onTime
    }

    var expectedDeparture: Date {
        plannedDeparture.addingTimeInterval(TimeInterval((departureDelay ?? 0) * 60))
    }

    /// Y a-t-il un problème selon le seuil de retard choisi ?
    func isProblem(threshold: Int) -> Bool {
        switch state {
        case .cancelled: return true
        case .delayed(let minutes): return minutes >= threshold
        default: return false
        }
    }
}

// MARK: - Rapport sur un trajet

/// Résultat d'une vérification : le train "principal" et les suivants.
struct TripReport: Codable, Hashable {
    let trip: Trip
    /// Train surveillé (celui de l'heure habituelle, ou le prochain).
    let focus: ConnectionInfo?
    /// Trains suivants (alternatives).
    let upcoming: [ConnectionInfo]
    let fetchedAt: Date

    var severity: Severity {
        guard let focus else { return .unknown }
        if focus.isCancelled { return .critical }
        if focus.isProblem(threshold: trip.delayThreshold) { return .warning }
        if case .unknown = focus.state { return .unknown }
        return .ok
    }

    /// Premier train non supprimé après le train surveillé (utile en cas de suppression).
    var nextAlternative: ConnectionInfo? {
        upcoming.first { !$0.isCancelled && $0.id != focus?.id }
    }

    enum Severity: Int, Codable {
        case unknown, ok, warning, critical
    }
}

// MARK: - Numéro de gare commun à toutes les sources

enum StationNumber {
    /// Ramène les différents formats d'identifiant de gare au même numéro court :
    /// "8501120" (numéro UIC) -> "1120", "ch:1:sloid:1120" (sloid) -> "1120".
    static func short(_ id: String) -> String? {
        let parts = id.split(separator: ":")
        if parts.count >= 4 && parts[2] == "sloid" {
            return Int(parts[3]).map(String.init)
        }
        guard let number = Int(id) else { return nil }
        // Gares suisses : 85 + numéro sur 5 chiffres.
        if (8_500_000..<8_600_000).contains(number) { return String(number - 8_500_000) }
        return String(number)
    }
}

// MARK: - Perturbation ou travaux concernant un trajet

/// Version simplifiée d'une alerte du réseau, enregistrée pour un trajet (lisible par le widget).
struct TripNetworkAlert: Codable, Hashable, Identifiable {
    let id: String
    let title: String
    let details: String
    let isConstruction: Bool
    let isInterruption: Bool
    /// Plage qui touche le trajet (ex. travaux ce soir 20:30 → 04:00).
    let start: Date?
    let end: Date?

    var isActiveNow: Bool {
        (start ?? .distantPast) <= .now && (end ?? .distantFuture) >= .now
    }

    /// "Travaux", "Interruption", "Perturbation"
    var label: String {
        if isConstruction { return isInterruption ? t("Travaux · interruption") : t("Travaux") }
        return isInterruption ? t("Interruption") : t("Perturbation")
    }

    /// "maintenant", "ce soir 20:30 → 04:00", "jeu. 2 oct., 22:00 → 05:00"
    var whenText: String {
        guard let start else { return t("en cours") }
        if isActiveNow {
            return end.map { t("jusqu'à %@", Formatting.time($0)) } ?? t("en cours")
        }
        let endText = end.map { " → \(Formatting.time($0))" } ?? ""
        return Formatting.dayTime(start) + endText
    }
}
