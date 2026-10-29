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
    /// Départ annoncé en avance (fréquent pour les bus) : on risque de le rater.
    case early(minutes: Int)
    case cancelled
    case unknown
}

/// Message officiel sur un train (perturbation, travaux, bus de remplacement, ascenseur en panne...).
struct ServiceMessage: Codable, Hashable, Identifiable {
    /// Numéro officiel du message (ou identifiant créé par l'app pour les cas détectés dans l'horaire).
    let id: String
    /// Phrase courte, ex. « Le trafic ferroviaire entre Palézieux et Romont FR est restreint. »
    let summary: String
    /// Cause, détails, recommandation et durée, quand ils existent.
    let details: String
    /// `false` pour une information qui ne retarde pas le train (accessibilité d'une gare, par exemple).
    let affectsService: Bool
    /// Message prévu à l'avance (travaux) ou survenu en temps réel (accident, panne...).
    let isPlanned: Bool
}

/// Une étape du trajet : un train, un bus, un tram... entre deux arrêts.
struct TripLeg: Codable, Hashable, Identifiable {
    /// "rail", "bus", "tram", "metro", "water", "cableway"...
    let mode: String
    let line: String?
    let destination: String?
    let fromName: String
    let toName: String
    let plannedDeparture: Date
    let departureDelay: Int?
    let plannedArrival: Date
    let arrivalDelay: Int?
    let departureTrack: String?
    let plannedDepartureTrack: String?
    let arrivalTrack: String?
    let isCancelled: Bool
    let isReplacementBus: Bool
    /// Temps de marche prévu avant cette étape (changement de quai), en minutes.
    let walkMinutesBefore: Int?

    var id: String { "\(line ?? mode)-\(Int(plannedDeparture.timeIntervalSince1970))-\(fromName)" }

    var expectedDeparture: Date { plannedDeparture.addingTimeInterval(TimeInterval((departureDelay ?? 0) * 60)) }
    var expectedArrival: Date {
        plannedArrival.addingTimeInterval(TimeInterval((arrivalDelay ?? departureDelay ?? 0) * 60))
    }

    var departureTrackChanged: Bool {
        guard let departureTrack, let plannedDepartureTrack else { return false }
        return departureTrack != plannedDepartureTrack
    }

    var departureState: DepartureState {
        if isCancelled { return .cancelled }
        guard let delay = departureDelay else { return .unknown }
        if delay > 0 { return .delayed(minutes: delay) }
        if delay < 0 { return .early(minutes: -delay) }
        return .onTime
    }
}

/// Correspondance qui risque d'être manquée à cause d'un retard.
struct TransferRisk: Hashable {
    /// Index de l'étape suivante dans `legs`.
    let nextLegIndex: Int
    let station: String
    /// Minutes entre l'arrivée estimée et le départ estimé suivant (peut être négatif).
    let marginMinutes: Int
    /// Minutes nécessaires (marche prévue, au moins 1).
    let neededMinutes: Int
    var isMissed: Bool { marginMinutes < 0 }
}

/// Une correspondance renvoyée par l'horaire (OJP 2.0).
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
    /// La voie a changé par rapport à l'horaire.
    var trackChanged: Bool = false
    /// Affluence prévue, 1 = faible, 2 = moyenne, 3 = forte (nil = inconnue).
    var occupancyFirstClass: Int? = nil
    var occupancySecondClass: Int? = nil
    /// Voie prévue à l'horaire (différente de `track` quand la voie a changé).
    var plannedTrack: String? = nil
    /// Tous les messages officiels qui concernent ce train (y compris ceux sans effet sur la circulation).
    var messages: [ServiceMessage]? = nil
    /// Toutes les étapes du trajet, correspondances comprises.
    var legs: [TripLeg]? = nil

    /// Correspondances menacées : l'arrivée estimée laisse moins de temps que la marche prévue.
    var transferRisks: [TransferRisk] {
        guard let legs, legs.count > 1 else { return [] }
        var risks: [TransferRisk] = []
        for index in 1..<legs.count {
            let previous = legs[index - 1], next = legs[index]
            guard !previous.isCancelled, !next.isCancelled,
                  previous.arrivalDelay != nil || next.departureDelay != nil else { continue }
            let margin = Int((next.expectedDeparture.timeIntervalSince(previous.expectedArrival) / 60).rounded(.down))
            let needed = max(next.walkMinutesBefore ?? 1, 1)
            let plannedMargin = Int(next.plannedDeparture.timeIntervalSince(previous.plannedArrival) / 60)
            // On ne signale que si la situation s'est dégradée par rapport à l'horaire.
            if margin < needed && margin < plannedMargin {
                risks.append(TransferRisk(nextLegIndex: index, station: next.fromName,
                                          marginMinutes: margin, neededMinutes: needed))
            }
        }
        return risks
    }

    var id: String { "\(line ?? "-")-\(Int(plannedDeparture.timeIntervalSince1970))" }

    var state: DepartureState {
        if isCancelled { return .cancelled }
        guard let delay = departureDelay else { return .unknown }
        if delay > 0 { return .delayed(minutes: delay) }
        if delay < 0 { return .early(minutes: -delay) }
        return .onTime
    }

    var expectedDeparture: Date {
        plannedDeparture.addingTimeInterval(TimeInterval((departureDelay ?? 0) * 60))
    }

    var expectedArrival: Date {
        plannedArrival.addingTimeInterval(TimeInterval((arrivalDelay ?? departureDelay ?? 0) * 60))
    }

    /// Affluence en 2e classe (la plus utile), sinon en 1re.
    var occupancy: Occupancy? {
        (occupancySecondClass ?? occupancyFirstClass).flatMap(Occupancy.init(rawValue:))
    }

    /// Y a-t-il un problème selon le seuil de retard choisi ?
    func isProblem(threshold: Int) -> Bool {
        switch state {
        case .cancelled: return true
        case .delayed(let minutes): return minutes >= threshold
        case .early(let minutes): return minutes >= 1 // partir en avance fait rater le bus ou le train
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

    /// Meilleure alternative quand le train surveillé a un problème :
    /// le train non supprimé qui arrive le plus tôt, s'il arrive avant le train surveillé (ou si celui-ci est supprimé).
    var bestAlternative: ConnectionInfo? {
        guard let focus else { return nil }
        let candidates = upcoming.filter { !$0.isCancelled && $0.id != focus.id && $0.expectedDeparture >= Date().addingTimeInterval(-60) }
        guard let best = candidates.min(by: { $0.expectedArrival < $1.expectedArrival }) else { return nil }
        if focus.isCancelled { return best }
        return best.expectedArrival < focus.expectedArrival ? best : nil
    }

    enum Severity: Int, Codable {
        case unknown, ok, warning, critical
    }
}

// MARK: - Affluence

/// Affluence prévue dans le train (échelle des CFF en 3 niveaux).
enum Occupancy: Int, Codable {
    case low = 1, medium = 2, high = 3

    var label: String {
        switch self {
        case .low: return t("Peu de monde")
        case .medium: return t("Assez chargé")
        case .high: return t("Très chargé")
        }
    }

    /// Nombre de silhouettes à afficher (1 à 3).
    var level: Int { rawValue }
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

    /// Numéro UIC complet d'une gare suisse (ex. "ch:1:sloid:1120" ou "1120" -> "8501120").
    static func uic(_ id: String) -> String? {
        guard let shortNumber = short(id), let number = Int(shortNumber) else { return nil }
        return number < 100_000 ? String(8_500_000 + number) : String(number)
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
