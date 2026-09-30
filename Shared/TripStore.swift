import Foundation

/// Sauvegarde des trajets dans l'App Group, pour que le widget puisse les lire.
final class TripStore {
    static let shared = TripStore()

    private let defaults: UserDefaults
    private let tripsKey = "trips.v1"
    private let notifiedKey = "notified.v1"
    private let reportsKey = "reports.v1"
    private let networkAlertsKey = "networkAlerts.v1"
    private let notifiedAlertsKey = "notifiedAlerts.v1"

    init() {
        // Si l'App Group n'est pas configuré, on retombe sur le stockage local de l'app
        // (le widget ne verra alors pas les trajets).
        defaults = UserDefaults(suiteName: AppConfig.appGroupID) ?? .standard
    }

    // MARK: Trajets

    func loadTrips() -> [Trip] {
        guard let data = defaults.data(forKey: tripsKey),
              let trips = try? JSONDecoder().decode([Trip].self, from: data)
        else { return [] }
        return trips
    }

    func saveTrips(_ trips: [Trip]) {
        guard let data = try? JSONEncoder().encode(trips) else { return }
        defaults.set(data, forKey: tripsKey)
    }

    // MARK: Derniers rapports (affichage immédiat au lancement, secours pour le widget)

    func loadReports() -> [UUID: TripReport] {
        guard let data = defaults.data(forKey: reportsKey),
              let reports = try? JSONDecoder().decode([UUID: TripReport].self, from: data)
        else { return [:] }
        return reports
    }

    func saveReport(_ report: TripReport) {
        var reports = loadReports()
        reports[report.trip.id] = report
        // On ne garde que les trajets qui existent encore.
        let ids = Set(loadTrips().map(\.id))
        reports = reports.filter { ids.contains($0.key) }
        if let data = try? JSONEncoder().encode(reports) {
            defaults.set(data, forKey: reportsKey)
        }
    }

    // MARK: Perturbations et travaux touchant chaque trajet (calculés par l'app, lus par le widget)

    func loadNetworkAlerts() -> [UUID: [TripNetworkAlert]] {
        guard let data = defaults.data(forKey: networkAlertsKey),
              let alerts = try? JSONDecoder().decode([UUID: [TripNetworkAlert]].self, from: data)
        else { return [:] }
        return alerts
    }

    func saveNetworkAlerts(_ alerts: [UUID: [TripNetworkAlert]]) {
        if let data = try? JSONEncoder().encode(alerts) {
            defaults.set(data, forKey: networkAlertsKey)
        }
    }

    /// Alertes réseau déjà notifiées pour un trajet (identifiants).
    func notifiedAlertIDs(for tripID: UUID) -> Set<String> {
        let dict = defaults.dictionary(forKey: notifiedAlertsKey) as? [String: [String]] ?? [:]
        return Set(dict[tripID.uuidString] ?? [])
    }

    func setNotifiedAlertIDs(_ ids: Set<String>, for tripID: UUID) {
        var dict = defaults.dictionary(forKey: notifiedAlertsKey) as? [String: [String]] ?? [:]
        dict[tripID.uuidString] = Array(ids)
        defaults.set(dict, forKey: notifiedAlertsKey)
    }

    // MARK: Anti-doublon des notifications

    /// Dernier état notifié pour un trajet (évite d'envoyer 10 fois la même alerte).
    func lastNotifiedSignature(for tripID: UUID) -> String? {
        (defaults.dictionary(forKey: notifiedKey) as? [String: String])?[tripID.uuidString]
    }

    func setLastNotifiedSignature(_ signature: String, for tripID: UUID) {
        var dict = (defaults.dictionary(forKey: notifiedKey) as? [String: String]) ?? [:]
        dict[tripID.uuidString] = signature
        defaults.set(dict, forKey: notifiedKey)
    }
}
