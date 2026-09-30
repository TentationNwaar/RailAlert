import Foundation

/// Réglages globaux partagés entre l'app et le widget.
enum AppConfig {
    /// App Group : espace de stockage commun à l'app et au widget.
    /// Doit être identique dans Config/RedAlert.entitlements et Config/RedAlertWidget.entitlements.
    static let appGroupID = "group.ch.maxweyermann.redalert"

    /// Identifiant de la tâche d'arrière-plan (doit aussi figurer dans Config/RedAlert-Info.plist).
    static let backgroundRefreshID = "ch.maxweyermann.redalert.refresh"

    /// Nom du widget (utilisé pour demander son rafraîchissement).
    static let widgetKind = "TripStatusWidget"

    /// Les horaires suisses sont exprimés en heure de Zurich.
    static let swissTimeZone = TimeZone(identifier: "Europe/Zurich") ?? .current

    static var swissCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = swissTimeZone
        calendar.locale = Locale(identifier: "fr_CH")
        return calendar
    }
}
