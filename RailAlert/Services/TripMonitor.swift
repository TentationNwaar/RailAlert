import Foundation
import BackgroundTasks
import UserNotifications

/// Programme les vérifications en arrière-plan.
///
/// Important : iOS décide lui-même quand lancer ces tâches (souvent toutes les 15 à 60 min,
/// davantage si l'app est utilisée souvent, moins si la batterie est faible).
/// Le serveur push (dossier Server/) rend les alertes fiables à la minute près.
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

/// Vérifie les trajets et envoie une notification locale quand un problème apparaît :
/// retard, suppression, changement de voie, perturbation ou travaux sur le parcours.
/// Quand le serveur push est actif, c'est lui qui envoie les notifications (pas de doublon).
enum TripMonitor {
    static func checkAll(now: Date = .now) async {
        // Version gratuite : seuls les premiers trajets (Premium.freeTripLimit) sont surveillés.
        let allTrips = Premium.monitoredTrips(TripStore.shared.loadTrips())
        var reports = TripStore.shared.loadReports()
        let sendLocal = !ServerSync.isEnabled

        // 1. Horaire en temps réel : pour les trajets proches (retard, suppression, voie),
        //    et au moins une fois pour les autres (gares du parcours, prochain train).
        for trip in allTrips where trip.isInMonitoringWindow(now) || needsNewReport(reports[trip.id], now: now) {
            guard let report = try? await TripChecker.report(for: trip, now: now) else { continue }
            reports[trip.id] = report
            if sendLocal && trip.notificationsEnabled && trip.isInMonitoringWindow(now) {
                await notifyIfNeeded(report)
                await notifyTrackChange(report)
                await notifyMessages(report)
                await notifyTransfer(report)
            }
        }

        // 2. Perturbations et travaux sur le parcours de chaque trajet.
        guard let network = try? await AlertCache.shared.result() else { return }
        let matches = TripAlertMatcher.matchAll(trips: allTrips, reports: reports, alerts: network.alerts)
        if sendLocal {
            for trip in allTrips where trip.notificationsEnabled {
                await notifyNetworkAlerts(matches[trip.id] ?? [], for: trip, report: reports[trip.id])
            }
        }

        // 3. Mise à jour des trajets suivis en direct (Live Activity).
        await LiveActivityManager.updateAll(reports: reports, networkAlerts: matches)
    }

    /// Pas encore de rapport, ou le train de référence est déjà passé.
    private static func needsNewReport(_ report: TripReport?, now: Date) -> Bool {
        guard let focus = report?.focus else { return true }
        return focus.plannedArrival < now
    }

    // MARK: Retard et suppression

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

        let time = Formatting.time(focus.plannedDeparture)
        let line = focus.line.map { " (\($0))" } ?? ""
        var title: String
        var body: String

        if focus.isCancelled {
            title = t("Train supprimé : %@", trip.title)
            body = t("Le train de %@%@ est supprimé.", time, line)
        } else if case .early(let minutes) = focus.state {
            title = t("Départ en avance : %@", trip.title)
            body = t("Le départ de %@%@ est annoncé %ld min plus tôt, à %@.", time, line, minutes,
                     Formatting.time(focus.expectedDeparture))
        } else {
            let delay = focus.departureDelay ?? 0
            title = t("Retard de %ld min : %@", delay, trip.title)
            body = t("Le train de %@%@ partira vers %@.", time, line, Formatting.time(focus.expectedDeparture))
        }
        // Alternative : le train qui arrive le plus tôt (Rail Alert+).
        if Premium.isActive, let alternative = report.bestAlternative {
            body += "\n" + t("Alternative : %@", Formatting.alternativeText(alternative))
        }
        if let notice = focus.notices.first {
            body += "\n\(notice)"
        }
        if title.isEmpty { title = trip.title }
        await send(id: "trip-\(trip.id.uuidString)", title: title, body: body, trip: trip, urgent: true)
    }

    /// Identifiant de l'état : on ne renotifie que si l'état change vraiment
    /// (supprimé, ou retard qui passe dans une nouvelle tranche de 5 min).
    private static func signatureFor(_ c: ConnectionInfo, threshold: Int) -> String {
        let base = String(Int(c.plannedDeparture.timeIntervalSince1970))
        if c.isCancelled { return base + "-X" }
        if case .early(let minutes) = c.state { return base + "-E\(minutes)" }
        guard let delay = c.departureDelay, delay >= threshold else { return base + "-ok" }
        return base + "-D\(min(delay / 5, 12))"
    }

    // MARK: Changement de voie

    /// Notifie quand la voie du train surveillé change :
    /// soit search.ch la marque comme modifiée, soit elle diffère de la dernière voie vue pour ce train.
    static func notifyTrackChange(_ report: TripReport) async {
        let trip = report.trip
        guard let focus = report.focus, let track = focus.track, !focus.isCancelled else { return }

        let seenKey = "\(focus.id)|\(track)"
        let lastSeen = TripStore.shared.value("lastTrack", for: trip.id)
        TripStore.shared.setValue(seenKey, "lastTrack", for: trip.id)

        // Voie vue lors de la dernière vérification, sinon voie prévue à l'horaire.
        let previousTrack: String? = {
            if let lastSeen, lastSeen.hasPrefix(focus.id + "|") {
                let seen = String(lastSeen.dropFirst(focus.id.count + 1))
                if seen != track { return seen }
            }
            return focus.trackChanged ? focus.plannedTrack : nil
        }()
        let changed = focus.trackChanged || (previousTrack != nil && previousTrack != track)
        guard changed else { return }

        // Une seule notification par train et par voie.
        guard TripStore.shared.value("notifiedTrack", for: trip.id) != seenKey else { return }
        TripStore.shared.setValue(seenKey, "notifiedTrack", for: trip.id)

        let time = Formatting.time(focus.plannedDeparture)
        let title = t("Changement de voie : %@", trip.title)
        let body = previousTrack.map { t("Le train de %@ part de la voie %@ (au lieu de %@).", time, track, $0) }
            ?? t("Le train de %@ part de la voie %@.", time, track)
        await send(id: "track-\(trip.id.uuidString)", title: title, body: body, trip: trip, urgent: true)
    }

    // MARK: Correspondance menacée

    /// Prévient quand un retard rend une correspondance serrée ou impossible (une fois par état).
    static func notifyTransfer(_ report: TripReport) async {
        let trip = report.trip
        guard let focus = report.focus, !focus.isCancelled, let risk = focus.transferRisks.first else { return }
        let key = "\(focus.id)|\(risk.nextLegIndex)|\(risk.isMissed ? "missed" : "tight")"
        guard TripStore.shared.value("notifiedTransfer", for: trip.id) != key else { return }
        TripStore.shared.setValue(key, "notifiedTransfer", for: trip.id)

        let title = risk.isMissed
            ? t("Correspondance compromise : %@", trip.title)
            : t("Correspondance serrée : %@", trip.title)
        var body = risk.isMissed
            ? t("Avec le retard, la correspondance à %@ sera probablement manquée, sauf si elle attend.", risk.station)
            : t("Il ne restera que %ld min pour changer à %@.", max(risk.marginMinutes, 0), risk.station)
        if Premium.isActive, let alternative = report.bestAlternative {
            body += "\n" + t("Alternative : %@", Formatting.alternativeText(alternative))
        }
        await send(id: "transfer-\(trip.id.uuidString)", title: title, body: body, trip: trip, urgent: true)
    }

    // MARK: Messages officiels sur le train surveillé

    /// Notifie chaque message officiel qui peut retarder ou interrompre le train surveillé
    /// (accident, panne, bus de remplacement, itinéraire modifié...), une seule fois par message.
    /// Les travaux prévus à l'avance sont déjà annoncés par les alertes du réseau : on ne les répète
    /// que si aucune alerte réseau ne concerne ce trajet.
    static func notifyMessages(_ report: TripReport) async {
        let trip = report.trip
        guard let focus = report.focus, !focus.isCancelled else { return }
        let hasNetworkAlerts = !(TripStore.shared.loadNetworkAlerts()[trip.id] ?? []).isEmpty
        let candidates = (focus.messages ?? []).filter { $0.affectsService && (!$0.isPlanned || !hasNetworkAlerts) }
        guard !candidates.isEmpty else { return }

        var notified = (TripStore.shared.value("notifiedMessages", for: trip.id) ?? "")
            .split(separator: "\n").map(String.init)
        for message in candidates where !notified.contains(message.id) {
            notified.append(message.id)
            let time = Formatting.time(focus.plannedDeparture)
            var body = t("Train de %@ : %@", time, message.summary)
            if !message.details.isEmpty { body += "\n" + message.details }
            await send(id: "message-\(trip.id.uuidString)-\(message.id)",
                       title: t("Info trafic : %@", trip.title), body: body,
                       trip: trip, urgent: !message.isPlanned)
        }
        // On garde les 40 derniers identifiants (pas de répétition, pas de croissance sans fin).
        TripStore.shared.setValue(notified.suffix(40).joined(separator: "\n"), "notifiedMessages", for: trip.id)
    }

    // MARK: Perturbations et travaux sur le parcours

    /// Notifie chaque perturbation ou chantier une seule fois par trajet.
    static func notifyNetworkAlerts(_ alerts: [TripNetworkAlert], for trip: Trip, report: TripReport?) async {
        let alreadyNotified = TripStore.shared.notifiedAlertIDs(for: trip.id)
        let currentIDs = Set(alerts.map(\.id))
        let fresh = alerts.filter { !alreadyNotified.contains($0.id) }
        // On oublie les alertes terminées, on ajoute les nouvelles.
        TripStore.shared.setNotifiedAlertIDs(alreadyNotified.intersection(currentIDs).union(fresh.map(\.id)), for: trip.id)

        for alert in fresh {
            let title = t("%@ sur ton trajet %@", alert.label, trip.title)
            var body = alert.title
            body += alert.isActiveNow ? t(" (en cours)") : " (\(alert.whenText))"
            if Premium.isActive, alert.isInterruption, let alternative = report?.bestAlternative ?? report?.nextAlternative {
                body += "\n" + t("Alternative : %@", Formatting.alternativeText(alternative))
            }
            if !alert.details.isEmpty {
                body += "\n" + alert.details
            }
            await send(id: "network-\(trip.id.uuidString)-\(alert.id)", title: title, body: body,
                       trip: trip, urgent: alert.isInterruption)
        }
    }

    // MARK: Envoi

    private static func send(id: String, title: String, body: String, trip: Trip, urgent: Bool) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.threadIdentifier = trip.id.uuidString
        content.interruptionLevel = urgent ? .timeSensitive : .active
        content.userInfo = ["tripID": trip.id.uuidString]
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
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
