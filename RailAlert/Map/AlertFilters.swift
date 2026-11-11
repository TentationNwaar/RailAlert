import Foundation
import MapKit

/// Les 7 grandes régions de Suisse (découpage de l'Office fédéral de la statistique).
enum SwissRegion: String, CaseIterable, Codable, Identifiable {
    case lemanique, mittelland, nordOuest, zurich, orientale, centrale, tessin

    var id: String { rawValue }

    var name: String {
        switch self {
        case .lemanique: return t("Région lémanique")
        case .mittelland: return t("Espace Mittelland")
        case .nordOuest: return t("Suisse du Nord-Ouest")
        case .zurich: return t("Zurich")
        case .orientale: return t("Suisse orientale")
        case .centrale: return t("Suisse centrale")
        case .tessin: return t("Tessin")
        }
    }

    var cantons: Set<String> {
        switch self {
        case .lemanique: return ["GE", "VD", "VS"]
        case .mittelland: return ["BE", "FR", "SO", "NE", "JU"]
        case .nordOuest: return ["BS", "BL", "AG"]
        case .zurich: return ["ZH"]
        case .orientale: return ["GL", "SH", "AR", "AI", "SG", "GR", "TG"]
        case .centrale: return ["LU", "UR", "SZ", "OW", "NW", "ZG"]
        case .tessin: return ["TI"]
        }
    }

    /// "GE · VD · VS"
    var cantonsText: String { cantons.sorted().joined(separator: " · ") }

    /// Rectangle approximatif (latitude min/max, longitude min/max) pour zoomer sur la région.
    var bounds: (minLat: Double, maxLat: Double, minLon: Double, maxLon: Double) {
        switch self {
        case .lemanique: return (45.82, 46.99, 5.95, 8.48)
        case .mittelland: return (46.30, 47.50, 6.43, 8.46)
        case .nordOuest: return (47.10, 47.70, 7.40, 8.46)
        case .zurich: return (47.16, 47.70, 8.36, 8.99)
        case .orientale: return (46.17, 47.81, 8.87, 10.49)
        case .centrale: return (46.54, 47.29, 7.84, 9.00)
        case .tessin: return (45.82, 46.64, 8.38, 9.16)
        }
    }

    /// Zone de carte couvrant plusieurs régions.
    static func mapRegion(for regions: Set<SwissRegion>) -> MKCoordinateRegion? {
        guard !regions.isEmpty else { return nil }
        let boxes = regions.map { $0.bounds }
        let minLat = boxes.map { $0.minLat }.min() ?? 45.8
        let maxLat = boxes.map { $0.maxLat }.max() ?? 47.8
        let minLon = boxes.map { $0.minLon }.min() ?? 5.9
        let maxLon = boxes.map { $0.maxLon }.max() ?? 10.5
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
            span: MKCoordinateSpan(latitudeDelta: (maxLat - minLat) * 1.15, longitudeDelta: (maxLon - minLon) * 1.15)
        )
    }
}

/// Choix de l'utilisateur : quelles alertes afficher. Enregistré sur l'iPhone.
struct AlertFilters: Codable, Equatable {
    /// Jusqu'où regarder pour les travaux.
    enum ConstructionHorizon: String, Codable, CaseIterable, Identifiable {
        case now, today, week
        var id: String { rawValue }
        var label: String {
            switch self {
            case .now: return t("En cours")
            case .today: return t("Aujourd'hui")
            case .week: return t("7 jours")
            }
        }
    }

    var showDisruptions = true
    var showConstruction = true
    /// Par défaut, seulement les travaux en cours : c'est moins chargé.
    var constructionHorizon: ConstructionHorizon = .now
    /// Afficher seulement les interruptions (rouge), pas les services restreints (jaune).
    var onlyInterruptions = false
    /// Informations diverses (accessibilité, informations sur un train précis...), dans la liste.
    var showInformation = false
    /// Régions choisies. Vide = toute la Suisse.
    var regions: Set<SwissRegion> = []

    static let `default` = AlertFilters()

    var isDefault: Bool { self == .default }

    /// L'alerte passe-t-elle les filtres ?
    func accepts(_ alert: RailAlert, now: Date = .now) -> Bool {
        switch alert.kind {
        case .disruption:
            if alert.severity == .info {
                guard showInformation else { return false }
            } else if !showDisruptions {
                return false
            }
        case .construction:
            guard showConstruction else { return false }
            switch constructionHorizon {
            case .now:
                guard alert.isActiveNow else { return false }
            case .today:
                let endOfDay = AppConfig.swissCalendar.startOfDay(for: now).addingTimeInterval(24 * 3600)
                if let window = alert.window, window.start > endOfDay { return false }
            case .week:
                break
            }
        }

        if onlyInterruptions && alert.severity != .interrupted { return false }

        if !regions.isEmpty {
            let wanted = regions.reduce(into: Set<String>()) { $0.formUnion($1.cantons) }
            guard !alert.cantons.isDisjoint(with: wanted) else { return false }
        }
        return true
    }

    /// Résumé court, ex. "Région lémanique · perturbations, travaux en cours".
    var summary: String {
        var parts: [String] = []
        switch regions.count {
        case 0: parts.append(t("Toute la Suisse"))
        case 1: parts.append(regions.first!.name)
        default: parts.append(t("%ld régions", regions.count))
        }
        var kinds: [String] = []
        if showDisruptions { kinds.append(onlyInterruptions ? t("interruptions") : t("perturbations")) }
        if showConstruction {
            switch constructionHorizon {
            case .now: kinds.append(t("travaux en cours"))
            case .today: kinds.append(t("travaux du jour"))
            case .week: kinds.append(t("travaux (7 j)"))
            }
        }
        if showInformation { kinds.append(t("infos")) }
        parts.append(kinds.isEmpty ? t("aucune alerte") : kinds.joined(separator: ", "))
        return parts.joined(separator: " · ")
    }

    // MARK: Enregistrement

    private static let storageKey = "alertFilters.v1"

    static func load() -> AlertFilters {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let filters = try? JSONDecoder().decode(AlertFilters.self, from: data)
        else { return .default }
        return filters
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}
