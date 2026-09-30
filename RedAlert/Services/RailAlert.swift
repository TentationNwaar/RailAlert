import Foundation
import CoreLocation
import MapKit
import SwiftUI

/// Un événement sur le réseau (perturbation ou travaux), placé sur la carte.
struct RailAlert: Identifiable, Hashable {
    enum Severity: Int, Comparable {
        case info = 0, limited = 1, interrupted = 2

        static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rawValue < rhs.rawValue }

        var color: Color {
            switch self {
            case .interrupted: return Theme.red
            case .limited, .info: return Theme.yellow
            }
        }

        var label: String {
            switch self {
            case .interrupted: return t("Service interrompu")
            case .limited: return t("Service restreint")
            case .info: return t("Information")
            }
        }
    }

    enum Kind: Hashable {
        case disruption
        case construction

        var label: String {
            switch self {
            case .disruption: return t("Perturbation")
            case .construction: return t("Travaux")
            }
        }

        /// Symbole dessiné dans le triangle.
        var symbol: String {
            switch self {
            case .disruption: return "exclamationmark"
            case .construction: return "hammer.fill"
            }
        }
    }

    let id: String
    let kind: Kind
    let severity: Severity
    /// Titre : tronçon concerné ou titre officiel du message.
    let section: String
    /// Texte détaillé.
    let details: String
    /// Langue du texte détaillé ("fr", "de", "it" ou "en"). Si ce n'est pas la langue choisie, l'app le traduit.
    let language: String
    /// Période globale (ex. du 16.08 au 12.12 pour un chantier).
    let start: Date?
    let end: Date?
    /// Plage en cours ou prochaine plage (ex. cette nuit 20:30 → 04:00 pour des travaux de nuit).
    let window: DateInterval?
    let link: URL?
    /// Gares géolocalisées, dans l'ordre le long de la ligne.
    let places: [Station]
    /// Cantons touchés (ex. ["VD", "FR"]). Vide si inconnu.
    var cantons: Set<String> = []
    /// Toutes les plages horaires connues (ex. chaque nuit de travaux). Vide = on utilise `window`.
    var periods: [DateInterval] = []

    /// L'événement a-t-il lieu pendant l'intervalle donné (ex. le trajet du matin) ?
    func overlaps(_ interval: DateInterval) -> Bool {
        let ranges = periods.isEmpty ? [window].compactMap { $0 } : periods
        guard !ranges.isEmpty else { return true }
        return ranges.contains { $0.start <= interval.end && $0.end >= interval.start }
    }

    var isOnMap: Bool { !places.isEmpty }

    /// L'événement a-t-il lieu en ce moment ?
    var isActiveNow: Bool {
        guard let window else { return true }
        return window.start <= .now && window.end >= .now
    }

    var isUpcoming: Bool { !isActiveNow }

    /// "En cours jusqu'à 04:00" ou "Prochaine fois : mer. 30 sept., 20:30 → 04:00"
    var windowText: String? {
        guard let window else { return nil }
        if isActiveNow { return t("En cours jusqu'à %@", Formatting.dayTime(window.end)) }
        return t("Prochaine fois : %@ → %@", Formatting.dayTime(window.start), Formatting.time(window.end))
    }

    var needsTranslation: Bool { language != AppLanguage.current.rawValue && !details.isEmpty }

    /// "Travaux · Service interrompu", "Service restreint", ...
    var headline: String {
        let base = kind == .construction ? t("Travaux · %@", severity.label) : severity.label
        return isUpcoming ? t("%@ · à venir", base) : base
    }

    /// Point où l'on dessine le triangle : milieu du tronçon.
    var coordinate: CLLocationCoordinate2D {
        guard !places.isEmpty else { return Theme.switzerlandCenter }
        let lat = places.map(\.latitude).reduce(0, +) / Double(places.count)
        let lon = places.map(\.longitude).reduce(0, +) / Double(places.count)
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    /// Zone à afficher quand on zoome sur l'alerte.
    var region: MKCoordinateRegion {
        let lats = places.map(\.latitude)
        let lons = places.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max()
        else { return Theme.switzerlandRegion }
        let latSpan = max((maxLat - minLat) * 1.8, 0.12)
        let lonSpan = max((maxLon - minLon) * 1.8, 0.12)
        // On décale le centre vers le sud pour que l'alerte reste visible au-dessus de la fiche.
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2 - latSpan * 0.22,
                                            longitude: (minLon + maxLon) / 2)
        return MKCoordinateRegion(center: center,
                                  span: MKCoordinateSpan(latitudeDelta: latSpan, longitudeDelta: lonSpan))
    }

    var periodText: String {
        switch (start, end) {
        case let (s?, e?): return "\(Formatting.dayTime(s)) → \(Formatting.dayTime(e))"
        case let (s?, nil): return t("Depuis %@", Formatting.dayTime(s))
        case let (nil, e?): return t("Jusqu'à %@", Formatting.dayTime(e))
        default: return t("Période inconnue")
        }
    }

    /// Remet des gares dans l'ordre le long de la ligne :
    /// on part de la gare la plus éloignée du centre, puis on trie par distance à cette gare.
    static func orderedAlongLine(_ stations: [Station]) -> [Station] {
        guard stations.count > 2 else { return stations }
        let lat = stations.map(\.latitude).reduce(0, +) / Double(stations.count)
        let lon = stations.map(\.longitude).reduce(0, +) / Double(stations.count)
        func distance(_ s: Station, _ la: Double, _ lo: Double) -> Double {
            let dLat = s.latitude - la
            let dLon = (s.longitude - lo) * cos(la * .pi / 180)
            return dLat * dLat + dLon * dLon
        }
        guard let extreme = stations.max(by: { distance($0, lat, lon) < distance($1, lat, lon) }) else { return stations }
        return stations.sorted { distance($0, extreme.latitude, extreme.longitude) < distance($1, extreme.latitude, extreme.longitude) }
    }
}

/// Choix de la source de données : avec une clé opentransportdata.swiss (travaux + français),
/// sinon data.sbb.ch (perturbations seulement, en anglais, traduites sur l'iPhone).
struct DisruptionService {
    enum Source {
        case sbb, openTransportData

        var label: String {
            switch self {
            case .sbb: return "data.sbb.ch"
            case .openTransportData: return "opentransportdata.swiss"
            }
        }
    }

    struct Result {
        let alerts: [RailAlert]
        let source: Source
        /// Message si la source principale a échoué et qu'on a utilisé la source de secours.
        let warning: String?
    }

    static let shared = DisruptionService()

    func fetchAlerts() async throws -> Result {
        let key = AppSettings.apiKey
        if !key.isEmpty {
            do {
                let alerts = try await OpenTransportDataSource().fetchAlerts(apiKey: key)
                return Result(alerts: sorted(alerts), source: .openTransportData, warning: nil)
            } catch {
                // Source de secours : on affiche quand même les perturbations CFF.
                let alerts = try await SBBRailInfoSource().fetchAlerts()
                return Result(alerts: sorted(alerts), source: .sbb,
                              warning: "opentransportdata.swiss : \(error.localizedDescription)")
            }
        }
        let alerts = try await SBBRailInfoSource().fetchAlerts()
        return Result(alerts: sorted(alerts), source: .sbb, warning: nil)
    }

    private func sorted(_ alerts: [RailAlert]) -> [RailAlert] {
        alerts.sorted { lhs, rhs in
            if lhs.severity != rhs.severity { return lhs.severity > rhs.severity }
            if lhs.kind != rhs.kind { return lhs.kind == .disruption }
            return (lhs.start ?? .distantPast) > (rhs.start ?? .distantPast)
        }
    }
}
