import Foundation
import UIKit

/// Lien avec le serveur push (dossier Server/ du projet).
///
/// Quand `Secrets.serverURL` est rempli :
/// 1. l'app demande un jeton push à Apple (nécessite la capacité « Push Notifications »,
///    donc un compte Apple Developer payant) ;
/// 2. elle envoie au serveur ce jeton, la langue choisie et la liste des trajets ;
/// 3. le serveur surveille les trajets chaque minute et envoie les alertes par push.
/// Tant que la dernière synchronisation a réussi, l'app n'envoie plus de notifications locales (pas de doublon).
enum ServerSync {
    private static let defaults = UserDefaults.standard
    private static let tokenKey = "server.deviceToken"
    private static let syncOKKey = "server.lastSyncOK"
    private static let liveTokensKey = "server.liveActivityTokens"

    static var isConfigured: Bool { !Secrets.serverURL.isEmpty }

    /// Le serveur s'occupe des alertes (configuré, jeton reçu, dernière synchronisation réussie).
    /// Valable aussi en version gratuite, pour les trajets qui ne sont pas en pause.
    static var isEnabled: Bool {
        isConfigured && deviceToken != nil && defaults.bool(forKey: syncOKKey)
    }

    static var deviceToken: String? { defaults.string(forKey: tokenKey) }

    // MARK: Jetons

    @MainActor
    static func registerForPushIfConfigured() {
        guard isConfigured else { return }
        UIApplication.shared.registerForRemoteNotifications()
    }

    static func setDeviceToken(_ data: Data) {
        defaults.set(data.map { String(format: "%02x", $0) }.joined(), forKey: tokenKey)
    }

    static func setLiveActivityToken(_ token: String, for tripID: UUID) {
        var tokens = defaults.dictionary(forKey: liveTokensKey) as? [String: String] ?? [:]
        tokens[tripID.uuidString] = token
        defaults.set(tokens, forKey: liveTokensKey)
    }

    // MARK: Synchronisation

    /// Envoie au serveur l'état complet (jeton, langue, trajets, suivis en direct). Sans effet si pas de serveur.
    static func sync() async {
        guard isConfigured, let token = deviceToken,
              let url = URL(string: Secrets.serverURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/v1/devices")
        else { return }

        // Version gratuite : le serveur surveille aussi les trajets qui ne sont pas en pause,
        // pour que les alertes arrivent sans ouvrir l'app. Rail Alert+ : tous les trajets.
        // Le suivi en direct (Live Activity) reste réservé à Rail Alert+.
        let trips = Premium.monitoredTrips(TripStore.shared.loadTrips())
        let liveTokens = defaults.dictionary(forKey: liveTokensKey) as? [String: String] ?? [:]
        let running = Premium.isActive ? trips.filter { LiveActivityManager.isRunning(tripID: $0.id) } : []

        #if DEBUG
        let environment = "sandbox"
        #else
        let environment = "production"
        #endif

        let payload = DevicePayload(
            deviceToken: token,
            environment: environment,
            language: AppLanguage.current.rawValue,
            trips: trips.map(TripPayload.init),
            liveActivities: running.compactMap { trip in
                liveTokens[trip.id.uuidString].map { LiveActivityPayload(tripId: trip.id.uuidString, token: $0) }
            }
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Secrets.serverAppKey, forHTTPHeaderField: "X-App-Key")
        request.httpBody = try? JSONEncoder().encode(payload)
        do {
            let (_, response) = try await HTTPClient.session.data(for: request)
            let ok = (response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false
            defaults.set(ok, forKey: syncOKKey)
        } catch {
            defaults.set(false, forKey: syncOKKey)
        }
    }
}

// MARK: - Format envoyé au serveur

private struct DevicePayload: Encodable {
    let deviceToken: String
    let environment: String
    let language: String
    let trips: [TripPayload]
    let liveActivities: [LiveActivityPayload]
}

private struct TripPayload: Encodable {
    let id: String
    let fromId: String
    let fromName: String
    let toId: String
    let toName: String
    let usualHour: Int?
    let usualMinute: Int?
    let weekdays: [Int]
    let notificationsEnabled: Bool
    let delayThreshold: Int

    init(_ trip: Trip) {
        id = trip.id.uuidString
        fromId = trip.from.id
        fromName = trip.from.name
        toId = trip.to.id
        toName = trip.to.name
        usualHour = trip.usualHour
        usualMinute = trip.usualMinute
        weekdays = trip.weekdays.sorted()
        notificationsEnabled = trip.notificationsEnabled
        delayThreshold = trip.delayThreshold
    }
}

private struct LiveActivityPayload: Encodable {
    let tripId: String
    let token: String
}
