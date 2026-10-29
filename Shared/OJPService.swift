import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// Horaire officiel en temps réel via OJP 2.0 (Open Journey Planner) d'opentransportdata.swiss.
/// Doc : https://opentransportdata.swiss/fr/cookbook/ (rubrique OJP 2.0)
///
/// Remplace search.ch (dont les conditions d'utilisation interdisent l'accès automatisé et l'usage commercial).
/// Contenu vérifié le 30.09.2026 sur des réponses réelles :
/// - heure prévue (`TimetabledTime`) et estimée (`EstimatedTime`), en UTC ;
/// - voie prévue (`PlannedQuay`) et réelle (`EstimatedQuay`) ;
/// - affluence par classe (`ExpectedDepartureOccupancy`) ;
/// - toutes les gares traversées (`LegIntermediate`), identifiées par leur sloid ;
/// - suppression (`Cancelled`, `NotServicedStop`).
struct OJPService {
    static let shared = OJPService()
    static let endpoint = URL(string: "https://api.opentransportdata.swiss/ojp20")!

    var isAvailable: Bool { !apiKey.isEmpty }

    private var apiKey: String { OJPConfig.apiKey }

    // MARK: Itinéraires

    func connections(fromID: String, toID: String, at date: Date, count: Int) async throws -> [ConnectionInfo] {
        let body = """
        <OJPTripRequest>
          <siri:RequestTimestamp>\(Self.iso(Date()))</siri:RequestTimestamp>
          <Origin><PlaceRef><StopPlaceRef>\(Self.escape(fromID))</StopPlaceRef><Name><Text>-</Text></Name></PlaceRef><DepArrTime>\(Self.iso(date))</DepArrTime></Origin>
          <Destination><PlaceRef><StopPlaceRef>\(Self.escape(toID))</StopPlaceRef><Name><Text>-</Text></Name></PlaceRef></Destination>
          <Params>
            <NumberOfResults>\(count)</NumberOfResults>
            <IncludeIntermediateStops>true</IncludeIntermediateStops>
            <UseRealtimeData>explanatory</UseRealtimeData>
          </Params>
        </OJPTripRequest>
        """
        let root = try await send(body)
        let situations = Self.situations(in: root)
        return root.descendants("TripResult").compactMap { Self.connection(from: $0, situations: situations) }
    }

    // MARK: Départs d'une gare

    func departures(stationID: String, at date: Date = .now, count: Int = 20) async throws -> [StationDeparture] {
        let body = """
        <OJPStopEventRequest>
          <siri:RequestTimestamp>\(Self.iso(Date()))</siri:RequestTimestamp>
          <Location><PlaceRef><StopPlaceRef>\(Self.escape(stationID))</StopPlaceRef><Name><Text>-</Text></Name></PlaceRef><DepArrTime>\(Self.iso(date))</DepArrTime></Location>
          <Params>
            <NumberOfResults>\(count)</NumberOfResults>
            <StopEventType>departure</StopEventType>
            <IncludePreviousCalls>false</IncludePreviousCalls>
            <IncludeOnwardCalls>false</IncludeOnwardCalls>
            <UseRealtimeData>explanatory</UseRealtimeData>
          </Params>
        </OJPStopEventRequest>
        """
        let root = try await send(body)
        // Un train en deux parties apparaît deux fois : on garde un seul départ par identifiant.
        var seen = Set<String>()
        return root.descendants("StopEventResult")
            .compactMap { Self.departure(from: $0) }
            .filter { seen.insert($0.id).inserted }
    }

    // MARK: Requête

    private func send(_ requestBody: String) async throws -> XMLElementNode {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <OJP xmlns="http://www.vdv.de/ojp" xmlns:siri="http://www.siri.org.uk/siri" version="2.0">
          <OJPRequest>
            <siri:ServiceRequest>
              <siri:ServiceRequestContext><siri:Language>\(AppLanguage.current.rawValue)</siri:Language></siri:ServiceRequestContext>
              <siri:RequestTimestamp>\(Self.iso(Date()))</siri:RequestTimestamp>
              <siri:RequestorRef>RedAlert_iOS</siri:RequestorRef>
              \(requestBody)
            </siri:ServiceRequest>
          </OJPRequest>
        </OJP>
        """
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/xml", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("RedAlert-iOS/1.0", forHTTPHeaderField: "User-Agent")
        request.httpBody = Data(xml.utf8)
        let (data, response) = try await HTTPClient.session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.badStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        guard let root = XMLElementNode.parse(data) else { throw APIError.unexpectedFormat }
        return root
    }

    // MARK: Lecture d'un itinéraire

    static func connection(from tripResult: XMLElementNode, situations: [String: ServiceMessage] = [:]) -> ConnectionInfo? {
        guard let trip = tripResult.child("Trip") else { return nil }
        let timedLegs = trip.children("Leg").compactMap { $0.child("TimedLeg") }
        guard let firstLeg = timedLegs.first, let lastLeg = timedLegs.last,
              let board = firstLeg.child("LegBoard"), let alight = lastLeg.child("LegAlight"),
              let plannedDeparture = date(board.path("ServiceDeparture", "TimetabledTime")?.text)
        else { return nil }

        let estimatedDeparture = date(board.path("ServiceDeparture", "EstimatedTime")?.text)
        let plannedArrival = date(alight.path("ServiceArrival", "TimetabledTime")?.text) ?? plannedDeparture
        let estimatedArrival = date(alight.path("ServiceArrival", "EstimatedTime")?.text)

        // Suppression : service supprimé, montée / descente non desservie,
        // ou arrêt où l'on ne peut plus monter (départ) ou descendre (arrivée).
        let cancelled = timedLegs.contains { leg in
            leg.path("Service", "Cancelled")?.text == "true"
                || leg.child("LegBoard")?.child("NotServicedStop")?.text == "true"
                || leg.child("LegAlight")?.child("NotServicedStop")?.text == "true"
                || leg.child("LegBoard")?.child("NoBoardingAtStop")?.text == "true"
                || leg.child("LegAlight")?.child("NoAlightingAtStop")?.text == "true"
        }
        let messages = serviceMessages(legs: timedLegs, situations: situations)
        let legs = tripLegs(trip)

        // Gares desservies, dans l'ordre.
        var stopIDs: [String] = []
        for leg in timedLegs {
            let calls = [leg.child("LegBoard")] + leg.children("LegIntermediate").map { Optional($0) } + [leg.child("LegAlight")]
            for call in calls.compactMap({ $0 }) {
                if let ref = call.child("StopPointRef")?.text {
                    let sloid = normalizeSloid(ref)
                    if stopIDs.last != sloid { stopIDs.append(sloid) }
                }
            }
        }

        let service = firstLeg.child("Service")
        let (plannedTrack, estimatedTrack) = (board.path("PlannedQuay", "Text")?.text, board.path("EstimatedQuay", "Text")?.text)
        let occupancy = occupancyLevels(board)

        return ConnectionInfo(
            plannedDeparture: plannedDeparture,
            plannedArrival: plannedArrival,
            departureDelay: estimatedDeparture.map { minutes(from: plannedDeparture, to: $0) },
            arrivalDelay: estimatedArrival.map { minutes(from: plannedArrival, to: $0) },
            isCancelled: cancelled,
            line: service.flatMap(lineName),
            track: estimatedTrack ?? plannedTrack,
            terminal: service?.path("DestinationText", "Text")?.text,
            transfers: Int(trip.child("Transfers")?.text ?? "") ?? max(timedLegs.count - 1, 0),
            notices: messages.filter(\.affectsService).map(\.summary),
            stopIDs: stopIDs,
            trackChanged: estimatedTrack != nil && plannedTrack != nil && estimatedTrack != plannedTrack,
            occupancyFirstClass: occupancy.first,
            occupancySecondClass: occupancy.second,
            plannedTrack: plannedTrack,
            messages: messages,
            legs: legs
        )
    }

    // MARK: Étapes du trajet

    /// Étapes en transport (train, bus...), avec le temps de marche prévu entre elles.
    static func tripLegs(_ trip: XMLElementNode) -> [TripLeg] {
        var legs: [TripLeg] = []
        var pendingWalk: Int?
        for leg in trip.children("Leg") {
            if let transfer = leg.child("TransferLeg") ?? leg.child("ContinuousLeg") {
                pendingWalk = (pendingWalk ?? 0) + (durationMinutes(transfer.child("Duration")?.text) ?? 0)
                continue
            }
            guard let timed = leg.child("TimedLeg"),
                  let board = timed.child("LegBoard"), let alight = timed.child("LegAlight"),
                  let plannedDeparture = date(board.path("ServiceDeparture", "TimetabledTime")?.text)
            else { continue }
            let plannedArrival = date(alight.path("ServiceArrival", "TimetabledTime")?.text) ?? plannedDeparture
            let estimatedDeparture = date(board.path("ServiceDeparture", "EstimatedTime")?.text)
            let estimatedArrival = date(alight.path("ServiceArrival", "EstimatedTime")?.text)
            let service = timed.child("Service")
            let plannedTrack = board.path("PlannedQuay", "Text")?.text
            legs.append(TripLeg(
                mode: service?.path("Mode", "PtMode")?.text ?? "rail",
                line: service.flatMap(lineName),
                destination: service?.path("DestinationText", "Text")?.text,
                fromName: board.path("StopPointName", "Text")?.text ?? "",
                toName: alight.path("StopPointName", "Text")?.text ?? "",
                plannedDeparture: plannedDeparture,
                departureDelay: estimatedDeparture.map { minutes(from: plannedDeparture, to: $0) },
                plannedArrival: plannedArrival,
                arrivalDelay: estimatedArrival.map { minutes(from: plannedArrival, to: $0) },
                departureTrack: board.path("EstimatedQuay", "Text")?.text ?? plannedTrack,
                plannedDepartureTrack: plannedTrack,
                arrivalTrack: alight.path("EstimatedQuay", "Text")?.text ?? alight.path("PlannedQuay", "Text")?.text,
                isCancelled: service?.child("Cancelled")?.text == "true"
                    || board.child("NotServicedStop")?.text == "true"
                    || alight.child("NotServicedStop")?.text == "true",
                isReplacementBus: service?.path("Mode", "BusSubmode")?.text == "railReplacementBus",
                walkMinutesBefore: legs.isEmpty ? nil : pendingWalk
            ))
            pendingWalk = nil
        }
        return legs
    }

    /// "PT5M" -> 5, "PT1H8M30S" -> 68 (minutes, arrondi vers le bas).
    static func durationMinutes(_ text: String?) -> Int? {
        guard let text, text.hasPrefix("PT") else { return nil }
        var total = 0.0
        var number = ""
        for char in text.dropFirst(2) {
            if char.isNumber || char == "." {
                number.append(char)
            } else {
                let value = Double(number) ?? 0
                switch char {
                case "H": total += value * 60
                case "M": total += value
                case "S": total += value / 60
                default: break
                }
                number = ""
            }
        }
        return Int(total)
    }

    // MARK: Messages officiels (SIRI-SX) et changements détectés dans l'horaire

    /// Causes qui ne retardent pas le train : on les montre, sans envoyer d'alerte.
    private static let accessibilityCauses: Set<String> = [
        "liftFailure", "escalatorFailure", "lifts", "escalators", "stairsOutOfService",
        "accessibilityProblem", "toiletsOutOfService"
    ]

    /// Tous les messages de la réponse, rangés par numéro (`SituationNumber`).
    static func situations(in root: XMLElementNode) -> [String: ServiceMessage] {
        var result: [String: ServiceMessage] = [:]
        for situation in root.descendants("PtSituation") {
            guard let number = situation.child("SituationNumber")?.text,
                  let content = situation.descendants("TextualContent").first,
                  let summary = content.path("SummaryContent", "SummaryText")?.text
            else { continue }
            let parts = [
                content.path("ReasonContent", "ReasonText")?.text,
                content.path("DescriptionContent", "DescriptionText")?.text,
                content.path("RecommendationContent", "RecommendationText")?.text,
                content.path("DurationContent", "DurationText")?.text
            ].compactMap { $0 }
            let cause = situation.child("AlertCause")?.text ?? ""
            result[number] = ServiceMessage(
                id: number,
                summary: summary,
                details: parts.joined(separator: "\n"),
                affectsService: !accessibilityCauses.contains(cause),
                isPlanned: situation.child("Planned")?.text == "true"
            )
        }
        return result
    }

    /// Messages d'un itinéraire : messages officiels liés aux trains utilisés,
    /// plus ce que l'horaire révèle (bus de remplacement, itinéraire dévié, train supplémentaire).
    static func serviceMessages(legs: [XMLElementNode], situations: [String: ServiceMessage]) -> [ServiceMessage] {
        var messages: [ServiceMessage] = []
        func add(_ message: ServiceMessage) {
            if !messages.contains(where: { $0.id == message.id }) { messages.append(message) }
        }
        for leg in legs {
            let journey = leg.path("Service", "JourneyRef")?.text ?? UUID().uuidString
            let from = leg.path("LegBoard", "StopPointName", "Text")?.text ?? ""
            let to = leg.path("LegAlight", "StopPointName", "Text")?.text ?? ""

            if leg.path("Service", "Mode", "BusSubmode")?.text == "railReplacementBus" {
                add(ServiceMessage(id: "bus-\(journey)",
                                   summary: t("Bus de remplacement entre %@ et %@.", from, to),
                                   details: t("Le train est remplacé par un bus sur ce tronçon. Prévois plus de temps."),
                                   affectsService: true, isPlanned: false))
            }
            if leg.descendants("Deviation").contains(where: { $0.text == "true" }) {
                add(ServiceMessage(id: "deviation-\(journey)",
                                   summary: t("Itinéraire modifié : ce train ne suit pas son parcours habituel."),
                                   details: "", affectsService: true, isPlanned: false))
            }
            if leg.descendants("Unplanned").contains(where: { $0.text == "true" }) {
                add(ServiceMessage(id: "extra-\(journey)",
                                   summary: t("Train supplémentaire, absent de l'horaire habituel."),
                                   details: "", affectsService: false, isPlanned: false))
            }
            for ref in leg.descendants("SituationFullRef") {
                if let number = ref.child("SituationNumber")?.text, let message = situations[number] {
                    add(message)
                }
            }
        }
        // Les messages qui touchent la circulation d'abord.
        return messages.filter(\.affectsService) + messages.filter { !$0.affectsService }
    }

    // MARK: Lecture d'un départ

    static func departure(from result: XMLElementNode) -> StationDeparture? {
        guard let event = result.child("StopEvent"),
              let call = event.path("ThisCall", "CallAtStop"),
              let planned = date(call.path("ServiceDeparture", "TimetabledTime")?.text)
        else { return nil }
        let service = event.child("Service")
        let estimated = date(call.path("ServiceDeparture", "EstimatedTime")?.text)
        let plannedTrack = call.path("PlannedQuay", "Text")?.text
        let estimatedTrack = call.path("EstimatedQuay", "Text")?.text
        let occupancy = occupancyLevels(call)
        return StationDeparture(
            id: (service?.child("JourneyRef")?.text ?? UUID().uuidString) + "-" + String(Int(planned.timeIntervalSince1970)),
            plannedTime: planned,
            delayMinutes: estimated.map { minutes(from: planned, to: $0) },
            isCancelled: service?.child("Cancelled")?.text == "true" || call.child("NotServicedStop")?.text == "true",
            line: service.flatMap(lineName) ?? "",
            destination: service?.path("DestinationText", "Text")?.text ?? "",
            track: estimatedTrack ?? plannedTrack,
            trackChanged: estimatedTrack != nil && plannedTrack != nil && estimatedTrack != plannedTrack,
            mode: service?.path("Mode", "PtMode")?.text ?? "rail",
            occupancy: (occupancy.second ?? occupancy.first).flatMap(Occupancy.init(rawValue:))
        )
    }

    // MARK: Outils

    /// "IR90" -> "IR 90", "S2" -> "S2", "ICE" -> "ICE"
    static func lineName(_ service: XMLElementNode) -> String? {
        guard let raw = service.path("PublishedServiceName", "Text")?.text ?? service.child("PublicCode")?.text else { return nil }
        guard let index = raw.firstIndex(where: \.isNumber), index != raw.startIndex else { return raw }
        let prefix = raw[..<index]
        // Les lignes S (RER) s'écrivent sans espace.
        return prefix == "S" || prefix == "SN" ? raw : "\(prefix) \(raw[index...])"
    }

    /// Affluence (1re, 2e classe) : 1 = places libres, 2 = peu de places, 3 = debout / complet.
    static func occupancyLevels(_ call: XMLElementNode) -> (first: Int?, second: Int?) {
        var first: Int?
        var second: Int?
        for item in call.children("ExpectedDepartureOccupancy") {
            let fareClass = (item.child("FareClass")?.text ?? "").trimmingCharacters(in: .whitespaces)
            let level: Int?
            switch (item.child("OccupancyLevel")?.text ?? "").trimmingCharacters(in: .whitespaces) {
            case "empty", "manySeatsAvailable", "seatsAvailable": level = 1
            case "fewSeatsAvailable": level = 2
            case "standingRoomOnly", "crushedStandingRoomOnly", "full", "notAcceptingPassengers": level = 3
            default: level = nil
            }
            if fareClass == "firstClass" { first = level } else if fareClass == "secondClass" { second = level }
        }
        return (first, second)
    }

    static func normalizeSloid(_ id: String) -> String {
        let parts = id.split(separator: ":")
        return parts.count >= 4 && parts[2] == "sloid" ? parts.prefix(4).joined(separator: ":") : id
    }

    static func minutes(from planned: Date, to estimated: Date) -> Int {
        Int((estimated.timeIntervalSince(planned) / 60).rounded())
    }

    private static let isoParser: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let isoParserFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func date(_ text: String?) -> Date? {
        guard let text else { return nil }
        return isoParser.date(from: text) ?? isoParserFractional.date(from: text)
    }

    static func iso(_ date: Date) -> String { isoParser.string(from: date) }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

/// Clé API pour OJP (application opentransportdata.swiss abonnée à "OJP 2.0").
enum OJPConfig {
    static var apiKey: String { Secrets.ojpKey.trimmingCharacters(in: .whitespacesAndNewlines) }
}

// MARK: - Départ affiché dans le tableau d'une gare

struct StationDeparture: Identifiable, Hashable {
    let id: String
    let plannedTime: Date
    let delayMinutes: Int?
    let isCancelled: Bool
    let line: String
    let destination: String
    let track: String?
    let trackChanged: Bool
    /// "rail", "bus", "tram", "water", "cableway"...
    let mode: String
    let occupancy: Occupancy?

    var expectedTime: Date { plannedTime.addingTimeInterval(TimeInterval((delayMinutes ?? 0) * 60)) }

    var state: DepartureState {
        if isCancelled { return .cancelled }
        guard let delay = delayMinutes else { return .unknown }
        if delay > 0 { return .delayed(minutes: delay) }
        if delay < 0 { return .early(minutes: -delay) }
        return .onTime
    }
}

// MARK: - Petit lecteur XML (arbre simple, sans les préfixes d'espace de noms)

final class XMLElementNode {
    let name: String
    var children: [XMLElementNode] = []
    var textBuffer = ""
    weak var parent: XMLElementNode?

    init(name: String) { self.name = name }

    var text: String? {
        let trimmed = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func child(_ name: String) -> XMLElementNode? { children.first { $0.name == name } }

    func children(_ name: String) -> [XMLElementNode] { children.filter { $0.name == name } }

    /// Chemin d'enfants successifs : path("ServiceDeparture", "EstimatedTime").
    func path(_ names: String...) -> XMLElementNode? {
        var node: XMLElementNode? = self
        for name in names { node = node?.child(name) }
        return node
    }

    /// Tous les descendants portant ce nom (parcours en profondeur).
    func descendants(_ name: String) -> [XMLElementNode] {
        var result: [XMLElementNode] = []
        for child in children {
            if child.name == name { result.append(child) }
            result.append(contentsOf: child.descendants(name))
        }
        return result
    }

    static func parse(_ data: Data) -> XMLElementNode? {
        let delegate = XMLTreeBuilder()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { return nil }
        return delegate.root
    }
}

private final class XMLTreeBuilder: NSObject, XMLParserDelegate {
    var root: XMLElementNode?
    private var current: XMLElementNode?

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        // "siri:StopPointRef" -> "StopPointRef"
        let localName = elementName.split(separator: ":").last.map(String.init) ?? elementName
        let node = XMLElementNode(name: localName)
        node.parent = current
        if let current { current.children.append(node) } else { root = node }
        current = node
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        current?.textBuffer += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        current = current?.parent
    }
}
