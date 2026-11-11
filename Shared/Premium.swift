import Foundation

/// Accès à Rail Alert+ (abonnement mensuel ou achat à vie).
///
/// L'état est enregistré dans l'App Group pour que l'app, le widget et Siri le lisent
/// sans attendre l'App Store. Il est recalculé par `StoreManager` à chaque lancement et après chaque achat.
///
/// Version gratuite : carte, filtres, départs, Siri, widget, et **2 trajets** surveillés (alertes en arrière-plan comprises).
/// Rail Alert+ : trajets illimités, suivi en direct, alternatives, ponctualité.
enum Premium {
    private static let key = "premium.active"
    private static var defaults: UserDefaults { UserDefaults(suiteName: AppConfig.appGroupID) ?? .standard }

    /// Nombre de trajets surveillés dans la version gratuite.
    static let freeTripLimit = 2

    static var isActive: Bool { defaults.bool(forKey: key) }

    static func setActive(_ active: Bool) {
        defaults.set(active, forKey: key)
    }

    /// Trajets réellement surveillés : tous avec Rail Alert+, sinon les premiers de la liste.
    static func monitoredTrips(_ trips: [Trip]) -> [Trip] {
        isActive ? trips : Array(trips.prefix(freeTripLimit))
    }

    /// Le trajet est en pause (version gratuite, au-delà des trajets gratuits).
    static func isPaused(_ trip: Trip, in trips: [Trip]) -> Bool {
        guard !isActive, let index = trips.firstIndex(where: { $0.id == trip.id }) else { return false }
        return index >= freeTripLimit
    }
}
