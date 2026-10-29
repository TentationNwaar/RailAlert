import Foundation
import ActivityKit

/// Données de la Live Activity "trajet en direct" (écran verrouillé + Dynamic Island).
/// Partagé entre l'app (qui la démarre et la met à jour) et le widget (qui l'affiche).
struct TripActivityAttributes: ActivityAttributes {
    /// Ce qui change pendant le trajet.
    struct ContentState: Codable, Hashable {
        var plannedDeparture: Date
        var expectedDeparture: Date
        var expectedArrival: Date
        var delayMinutes: Int?
        var isCancelled: Bool
        var track: String?
        var trackChanged: Bool
        var line: String?
        /// 0 = inconnu, 1 = à l'heure, 2 = retard, 3 = supprimé / interrompu (voir TripReport.Severity).
        var severity: Int
        /// Perturbation ou travaux sur le parcours (titre court).
        var alertText: String?
        /// Alternative proposée, ex. "07:53 IR 95 · arrivée 08:17".
        var alternativeText: String?
    }

    /// Ce qui ne change pas.
    var tripID: UUID
    var fromName: String
    var toName: String
}

extension TripActivityAttributes.ContentState {
    /// Construit l'état à partir d'un rapport de trajet et des alertes du réseau.
    init?(report: TripReport, networkAlerts: [TripNetworkAlert]) {
        guard let focus = report.focus else { return nil }
        let interruption = networkAlerts.contains(where: \.isInterruption)
        var severity = report.severity.rawValue
        if interruption { severity = TripReport.Severity.critical.rawValue }
        else if !networkAlerts.isEmpty && severity < TripReport.Severity.warning.rawValue {
            severity = TripReport.Severity.warning.rawValue
        }
        let alternative = report.bestAlternative.map(Formatting.alternativeText)
        self.init(plannedDeparture: focus.plannedDeparture,
                  expectedDeparture: focus.expectedDeparture,
                  expectedArrival: focus.expectedArrival,
                  delayMinutes: focus.departureDelay,
                  isCancelled: focus.isCancelled,
                  track: focus.track,
                  trackChanged: focus.trackChanged,
                  line: focus.line,
                  severity: severity,
                  alertText: networkAlerts.first?.title,
                  alternativeText: alternative)
    }
}
