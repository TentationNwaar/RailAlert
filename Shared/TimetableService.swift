import Foundation

/// Horaire en temps réel via l'API de search.ch (sans clé API).
/// Doc : https://search.ch/timetable/api/help
/// Limite : 1000 recherches d'itinéraire par jour.
///
/// Particularités du format :
/// - les heures sont en heure suisse, format "2026-09-30 09:23:00" ;
/// - `dep_delay` vaut "+0", "+3"... ou "X" quand le train est supprimé.
struct TimetableService {
    static let shared = TimetableService()

    private static let dateTimeParser: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = AppConfig.swissTimeZone
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    private static let dateParam: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = AppConfig.swissTimeZone
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let timeParam: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = AppConfig.swissTimeZone
        f.dateFormat = "HH:mm"
        return f
    }()

    /// Liste des correspondances entre deux gares à partir d'une date.
    func connections(from: Station, to: Station, at date: Date, count: Int = 5) async throws -> [ConnectionInfo] {
        guard let url = HTTPClient.url("https://search.ch/timetable/api/route.json", [
            ("from", from.id),
            ("to", to.id),
            ("date", Self.dateParam.string(from: date)),
            ("time", Self.timeParam.string(from: date)),
            ("num", String(count)),
            ("show_delays", "1"),
            ("show_trackchanges", "1")
        ]) else { throw APIError.invalidURL }

        let response = try await HTTPClient.get(url, as: RouteResponse.self)
        return (response.connections ?? []).compactMap(makeConnection)
    }

    // MARK: - Conversion

    private func makeConnection(_ c: RouteResponse.Connection) -> ConnectionInfo? {
        guard let depText = c.departure, let dep = Self.dateTimeParser.date(from: depText) else { return nil }
        let arr = c.arrival.flatMap { Self.dateTimeParser.date(from: $0) } ?? dep
        let legs = c.legs ?? []
        let rides = legs.filter { $0.line != nil || ($0.type != nil && $0.type != "walk") }
        let firstRide = rides.first

        // Suppression : "X" sur la correspondance ou sur un des tronçons.
        let delayFields = [c.dep_delay, c.arr_delay]
            + legs.map(\.dep_delay)
            + legs.map { $0.exit?.arr_delay }
        let cancelled = delayFields.contains { $0?.uppercased() == "X" }

        // Messages de perturbation (format peu documenté : on lit les textes connus).
        let keys: Set<String> = ["header", "lead", "title", "text"]
        var notices: [String] = []
        for value in [c.disruptions] + legs.map(\.disruptions) {
            for text in value?.texts(forKeys: keys) ?? [] {
                let clean = text.strippingHTML()
                if !clean.isEmpty && !notices.contains(clean) { notices.append(clean) }
            }
        }

        // Toutes les gares desservies, dans l'ordre (départ, arrêts intermédiaires, arrivée de chaque tronçon).
        var stopIDs: [String] = []
        func addStop(_ value: JSONValue?) {
            if let id = value?.textValue, !id.isEmpty, stopIDs.last != id { stopIDs.append(id) }
        }
        for leg in legs {
            addStop(leg.stopid)
            for stop in leg.stops ?? [] { addStop(stop.stopid) }
            addStop(leg.exit?.stopid)
        }

        return ConnectionInfo(
            plannedDeparture: dep,
            plannedArrival: arr,
            departureDelay: Self.parseDelay(c.dep_delay ?? firstRide?.dep_delay),
            arrivalDelay: Self.parseDelay(c.arr_delay ?? legs.last(where: { $0.exit != nil })?.exit?.arr_delay),
            isCancelled: cancelled,
            line: firstRide?.line,
            track: firstRide?.track,
            terminal: firstRide?.terminal?.stringValue,
            transfers: max(rides.count - 1, 0),
            notices: notices,
            stopIDs: stopIDs
        )
    }

    /// "+3" -> 3, "+0" -> 0, "X" ou nil -> nil
    static func parseDelay(_ text: String?) -> Int? {
        guard let text, text.uppercased() != "X" else { return nil }
        return Int(text.replacingOccurrences(of: "+", with: ""))
    }
}

// MARK: - Format de réponse de search.ch

private struct RouteResponse: Decodable {
    let connections: [Connection]?

    struct Connection: Decodable {
        let departure: String?
        let arrival: String?
        let dep_delay: String?
        let arr_delay: String?
        let legs: [Leg]?
        let disruptions: JSONValue?
    }

    struct Leg: Decodable {
        let line: String?
        let type: String?
        let track: String?
        let terminal: JSONValue?
        let dep_delay: String?
        let disruptions: JSONValue?
        let exit: Exit?
        let stopid: JSONValue?
        let stops: [Stop]?
    }

    struct Stop: Decodable {
        let stopid: JSONValue?
    }

    struct Exit: Decodable {
        let arr_delay: String?
        let stopid: JSONValue?
    }
}

extension String {
    /// Retire les balises HTML simples et remplace les <br> par des retours à la ligne.
    func strippingHTML() -> String {
        var text = self
        for br in ["<br />", "<br/>", "<br>", "</p>"] {
            text = text.replacingOccurrences(of: br, with: "\n", options: .caseInsensitive)
        }
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let entities = ["&amp;": "&", "&nbsp;": " ", "&quot;": "\"", "&#39;": "'", "&lt;": "<", "&gt;": ">"]
        for (entity, char) in entities {
            text = text.replacingOccurrences(of: entity, with: char)
        }
        text = text.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
