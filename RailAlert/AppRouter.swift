import Foundation

/// Navigation déclenchée depuis l'extérieur de l'app :
/// toucher une notification, le widget ou le suivi en direct ouvre directement le trajet concerné.
@MainActor
final class AppRouter: ObservableObject {
    static let shared = AppRouter()

    /// Trajet à ouvrir dès que l'onglet « Mes trajets » est affiché.
    @Published var pendingTripID: UUID?

    func openTrip(_ id: UUID) {
        pendingTripID = id
    }

    /// Lien du type `redalert://trip/<identifiant>` (widget, Live Activity).
    func handle(_ url: URL) {
        guard url.scheme == AppConfig.urlScheme, url.host == "trip",
              let id = UUID(uuidString: url.lastPathComponent)
        else { return }
        openTrip(id)
    }
}
