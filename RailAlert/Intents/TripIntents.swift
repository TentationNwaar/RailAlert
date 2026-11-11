import AppIntents
import Foundation

// MARK: - Trajet (pour choisir un trajet dans l'app Raccourcis)

struct TripEntity: AppEntity, Identifiable {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Trajet"
    static var defaultQuery = TripEntityQuery()

    let id: UUID
    let title: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)") }

    init(trip: Trip) {
        id = trip.id
        title = trip.title
    }
}

struct TripEntityQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [TripEntity] {
        TripStore.shared.loadTrips().filter { identifiers.contains($0.id) }.map(TripEntity.init)
    }

    func suggestedEntities() async throws -> [TripEntity] {
        TripStore.shared.loadTrips().map(TripEntity.init)
    }
}

// MARK: - "Mon train est-il à l'heure ?"

/// Répond (à voix haute avec Siri) sur l'état du prochain trajet habituel, sans ouvrir l'app.
struct CheckTripIntent: AppIntent {
    static var title: LocalizedStringResource = "Vérifier mon trajet"
    static var description = IntentDescription("Indique si ton train est à l'heure, en retard ou supprimé, et s'il y a des travaux sur le parcours.")
    static var openAppWhenRun = false

    @Parameter(title: "Trajet")
    var trip: TripEntity?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let trips = TripStore.shared.loadTrips()
        let chosen = trip.flatMap { entity in trips.first { $0.id == entity.id } }
            ?? TripChecker.mostRelevantTrip(in: Premium.monitoredTrips(trips))
        guard let chosen else {
            return .result(dialog: "\(t("Tu n'as pas encore de trajet. Ajoute-en un dans Rail Alert."))")
        }
        let report = try await TripChecker.report(for: chosen)
        let networkAlerts = TripStore.shared.loadNetworkAlerts()[chosen.id] ?? []
        return .result(dialog: "\(Self.sentence(for: report, networkAlerts: networkAlerts))")
    }

    /// Phrase complète, dans la langue choisie dans l'app.
    static func sentence(for report: TripReport, networkAlerts: [TripNetworkAlert]) -> String {
        let trip = report.trip
        guard let focus = report.focus else {
            return t("Aucun train trouvé pour %@.", trip.title)
        }
        let time = Formatting.time(focus.plannedDeparture)
        var parts: [String] = []
        switch focus.state {
        case .cancelled:
            parts.append(t("Ton train de %@ pour %@ est supprimé.", time, trip.to.name))
        case .delayed(let minutes):
            parts.append(t("Ton train de %@ pour %@ a %ld minutes de retard.", time, trip.to.name, minutes))
        case .early(let minutes):
            parts.append(t("Attention, ton train de %@ pour %@ part %ld minutes en avance.", time, trip.to.name, minutes))
        case .onTime:
            parts.append(t("Ton train de %@ pour %@ est à l'heure.", time, trip.to.name))
        case .unknown:
            parts.append(t("Ton train de %@ pour %@ n'a pas encore d'information en temps réel.", time, trip.to.name))
        }
        if let track = focus.track {
            parts.append(focus.trackChanged ? t("Attention, il part de la voie %@.", track) : t("Voie %@.", track))
        }
        if let alert = networkAlerts.first {
            parts.append(alert.label + " : " + alert.title)
        }
        if Premium.isActive, let alternative = report.bestAlternative {
            parts.append(t("Alternative : %@", Formatting.alternativeText(alternative)))
        }
        return parts.joined(separator: " ")
    }
}

// MARK: - Phrases Siri

/// Phrases reconnues par Siri (traduites dans AppShortcuts.xcstrings).
/// Chaque phrase doit contenir le nom de l'app.
struct RedAlertShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CheckTripIntent(),
            phrases: [
                "Mon train est à l’heure avec \(.applicationName)",
                "Vérifie mon trajet avec \(.applicationName)",
                "État de mon train dans \(.applicationName)"
            ],
            shortTitle: "Mon trajet",
            systemImageName: "tram.fill"
        )
    }
}
