import Foundation
import BackgroundTasks
import UserNotifications

/// Programme les vérifications en arrière-plan.
///
/// Important : iOS décide lui-même quand lancer ces tâches (souvent toutes les 15 à 60 min,
/// davantage si l'app est utilisée souvent, moins si la batterie est faible).
/// Pour des alertes garanties à la minute près, il faudra un serveur + notifications push (étape suivante).
enum BackgroundRefresh {
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: AppConfig.backgroundRefreshID)
        request.earliestBeginDate = Date().addingTimeInterval(15 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Échoue sur le simulateur : c'est normal.
            print("BackgroundRefresh: \(error.localizedDescription)")
        }
    }
}

/// Vérifie les trajets et envoie une notification locale quand un problème apparaît.
enum TripMonitor {
    static func checkAll(now: Date = .now) async {
        let allTrips = TripStore.shared.loadTrips()
        var reports = TripStore.shared.loadReports()

        // 1. Horaire en temps réel : pour les trajets proches (retard, suppression),
        //    et au moins une fois pour les autres (gares du parcours, prochain train).
        for trip in allTrips where trip.isInMonitoringWindow(now) || needsNewReport(reports[trip.id], now: now) {
            guard let report = try? await TripChecker.report(for: trip, now: now) else { continue }
            reports[trip.id] = report
            if trip.notificationsEnabled && trip.isInMonitoringWindow(now) {
                await notifyIfNeeded(report)
            }
        }

        // 2. Perturbations et travaux sur le parcours de chaque trajet.
        guard let network = try? await AlertCache.shared.result() else { return }
        let matches = TripAlertMatcher.matchAll(trips: allTrips, reports: reports, alerts: network.alerts)
        for trip in allTrips where trip.notificationsEnabled {
            await notifyNetworkAlerts(matches[trip.id] ?? [], for: trip)
        }
    }

    /// Pas encore de rapport, ou le train de référence est déjà passé.
    private static func needsNewReport(_ report: TripReport?, now: Date) -> Bool {
        guard let focus = report?.focus else { return true }
        return focus.plannedArrival < now
    }

    /// Notifie chaque perturbation ou chantier une seule fois par trajet.
    static func notifyNetworkAlerts(_ alerts: [TripNetworkAlert], for trip: Trip) async {
        let alreadyNotified = TripStore.shared.notifiedAlertIDs(for: trip.id)
        let currentIDs = Set(alerts.map(\.id))
        let fresh = alerts.filter { !alreadyNotified.contains($0.id) }
        // On oublie les alertes terminées, on ajoute les nouvelles.
        TripStore.shared.setNotifiedAlertIDs(alreadyNotified.intersection(currentIDs).union(fresh.map(\.id)), for: trip.id)

        for alert in fresh {
            let content = UNMutableNotificationContent()
            content.sound = .default
            content.threadIdentifier = trip.id.uuidString
            content.interruptionLevel = alert.isInterruption ? .timeSensitive : .active
            content.title = t("%@ sur ton trajet %@", alert.label, trip.title)
            var body = alert.title
            body += alert.isActiveNow ? t(" (en cours)") : " (\(alert.whenText))"
            if !alert.details.isEmpty {
                body += "\n" + alert.details
            }
            content.body = body
            let request = UNNotificationRequest(identifier: "network-\(trip.id.uuidString)-\(alert.id)",
                                                content: content, trigger: nil)
            try? await UNUserNotificationCenter.current().add(request)
        }
    }

    /// Envoie une notification seulement si l'état a changé depuis la dernière alerte.
    static func notifyIfNeeded(_ report: TripReport) async {
        let trip = report.trip
        guard let focus = report.focus else { return }

        let signature = signatureFor(focus, threshold: trip.delayThreshold)
        let previous = TripStore.shared.lastNotifiedSignature(for: trip.id)
        guard signature != previous else { return }
        TripStore.shared.setLastNotifiedSignature(signature, for: trip.id)

        // On n'alerte que pour les problèmes (pas pour "tout va bien").
        guard focus.isProblem(threshold: trip.delayThreshold) else { return }

        let content = UNMutableNotificationContent()
        content.sound = .default
        content.threadIdentifier = trip.id.uuidString
        content.interruptionLevel = .timeSensitive
        let time = Formatting.time(focus.plannedDeparture)
        let line = focus.line.map { " (\($0))" } ?? ""

        if focus.isCancelled {
            content.title = t("Train supprimé : %@", trip.title)
            var body = t("Le train de %@%@ est supprimé.", time, line)
            if let alt = report.nextAlternative {
                body += t(" Prochain départ : %@", Formatting.time(alt.expectedDeparture))
                body += alt.line.map { " (\($0))." } ?? "."
            }
            content.body = body
        } else {
            let delay = focus.departureDelay ?? 0
            content.title = t("Retard de %ld min : %@", delay, trip.title)
            content.body = t("Le train de %@%@ partira vers %@.", time, line, Formatting.time(focus.expectedDeparture))
        }
        if let notice = focus.notices.first {
            content.body += "\n\(notice)"
        }

        let request = UNNotificationRequest(identifier: "trip-\(trip.id.uuidString)", content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    /// Identifiant de l'état : on ne renotifie que si l'état change vraiment
    /// (supprimé, ou retard qui passe dans une nouvelle tranche de 5 min).
    private static func signatureFor(_ c: ConnectionInfo, threshold: Int) -> String {
        let base = String(Int(c.plannedDeparture.timeIntervalSince1970))
        if c.isCancelled { return base + "-X" }
        guard let delay = c.departureDelay, delay >= threshold else { return base + "-ok" }
        return base + "-D\(min(delay / 5, 12))"
    }

    // MARK: Autorisations

    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        return granted
    }

    /// Notification de démonstration, pour vérifier l'affichage sur l'écran verrouillé.
    static func sendTest(for trip: Trip) async {
        _ = await requestAuthorization()
        let content = UNMutableNotificationContent()
        content.title = t("Test : %@", trip.title)
        content.body = t("Voici à quoi ressemblera une alerte de retard ou de suppression.")
        content.sound = .default
        // Délai de 5 s : le temps de verrouiller l'iPhone.
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        let request = UNNotificationRequest(identifier: "test-\(UUID().uuidString)", content: content, trigger: trigger)
        try? await UNUserNotificationCenter.current().add(request)
    }
}
