import Foundation
import ActivityKit

/// Démarre, met à jour et arrête le suivi en direct d'un trajet (Live Activity).
///
/// Sans serveur push, la Live Activity est mise à jour quand l'app est ouverte ou lors
/// des vérifications en arrière-plan. Avec le serveur (Secrets.serverURL), elle reçoit
/// aussi des mises à jour par push : le jeton de la Live Activity est envoyé au serveur.
enum LiveActivityManager {
    typealias TripActivity = Activity<TripActivityAttributes>

    static func isRunning(tripID: UUID) -> Bool {
        TripActivity.activities.contains { $0.attributes.tripID == tripID }
    }

    /// Démarre le suivi. Renvoie `false` si les Live Activities sont désactivées ou si le trajet n'a pas de train.
    @discardableResult
    static func start(trip: Trip, report: TripReport, networkAlerts: [TripNetworkAlert]) -> Bool {
        guard Premium.isActive,
              ActivityAuthorizationInfo().areActivitiesEnabled,
              let state = TripActivityAttributes.ContentState(report: report, networkAlerts: networkAlerts)
        else { return false }

        // Un seul suivi par trajet.
        for activity in TripActivity.activities where activity.attributes.tripID == trip.id {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }

        let attributes = TripActivityAttributes(tripID: trip.id, fromName: trip.from.name, toName: trip.to.name)
        let content = ActivityContent(state: state, staleDate: state.expectedArrival.addingTimeInterval(20 * 60))
        do {
            let activity = try TripActivity.request(attributes: attributes, content: content,
                                                    pushType: ServerSync.isConfigured ? .token : nil)
            observePushToken(activity)
            return true
        } catch {
            print("Live Activity : \(error.localizedDescription)")
            return false
        }
    }

    static func stop(tripID: UUID) async {
        for activity in TripActivity.activities where activity.attributes.tripID == tripID {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        await ServerSync.sync()
    }

    /// Met à jour tous les suivis en cours. Un suivi se termine 10 min après l'arrivée du train suivi.
    static func updateAll(reports: [UUID: TripReport], networkAlerts: [UUID: [TripNetworkAlert]]) async {
        for activity in TripActivity.activities {
            let tripID = activity.attributes.tripID
            let current = activity.content.state

            // Train suivi arrivé depuis plus de 10 min : on termine.
            if current.expectedArrival < Date().addingTimeInterval(-10 * 60) {
                await activity.end(nil, dismissalPolicy: .default)
                continue
            }
            guard let report = reports[tripID],
                  let state = TripActivityAttributes.ContentState(report: report, networkAlerts: networkAlerts[tripID] ?? []),
                  // On ne passe pas au train du lendemain : on ne suit que le même train.
                  state.plannedDeparture == current.plannedDeparture || report.focus?.isCancelled == true
            else { continue }
            if state != current {
                await activity.update(ActivityContent(state: state, staleDate: state.expectedArrival.addingTimeInterval(20 * 60)))
            }
        }
    }

    /// Envoie au serveur le jeton qui permet de mettre à jour cette Live Activity par push.
    private static func observePushToken(_ activity: TripActivity) {
        guard ServerSync.isConfigured else { return }
        Task {
            for await tokenData in activity.pushTokenUpdates {
                let token = tokenData.map { String(format: "%02x", $0) }.joined()
                ServerSync.setLiveActivityToken(token, for: activity.attributes.tripID)
                await ServerSync.sync()
            }
        }
    }
}
