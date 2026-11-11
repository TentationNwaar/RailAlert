import Foundation

/// Source avec clé API : flux officiel "GTFS-RT Service Alerts" d'opentransportdata.swiss.
/// Il contient les perturbations ET les travaux de toute la Suisse, en DE / FR / IT / EN,
/// avec le calendrier complet de chaque chantier (plages horaires, souvent de nuit).
/// Doc : https://opentransportdata.swiss/fr/cookbook/event-cookbook/gtfs-sa/
///
/// Constaté le 30.09.2026 sur le flux réel :
/// - environ 1600 messages (bus, trams, trains), 14 Mo en JSON, 0,9 Mo compressé
///   (l'iPhone demande et décompresse automatiquement la version compressée) ;
/// - l'adresse renvoie (redirection) vers largeapi.opentransportdata.swiss ;
/// - limite du plan : 5 requêtes par minute.
struct OpenTransportDataSource {
    static let endpoint = "https://api.opentransportdata.swiss/la/gtfs-sa"

    /// Numéro d'entreprise des CFF dans les données suisses.
    static let sbbAgencyID = "11"

    /// Les travaux sont affichés s'ils ont lieu dans les 7 prochains jours.
    static let lookAhead: TimeInterval = 7 * 24 * 3600

    func fetchAlerts(apiKey: String, now: Date = .now) async throws -> [RailAlert] {
        guard let url = HTTPClient.url(Self.endpoint, [("format", "json")]) else { throw APIError.invalidURL }
        let feed = try await HTTPClient.get(url, as: FeedMessage.self,
                                            headers: ["Authorization": "Bearer \(apiKey)"])

        let raw = (feed.entity ?? []).compactMap { entity -> RawAlert? in
            guard let alert = entity.alert else { return nil }
            return RawAlert(id: entity.id ?? UUID().uuidString, alert: alert, now: now)
        }
        // Perturbations : en cours (ou dans les 3 h). Travaux : dans les 7 prochains jours.
        let relevant = raw.filter { alert in
            guard let window = alert.window else { return true }
            let horizon = alert.isConstruction ? Self.lookAhead : 3 * 3600
            return window.start <= now.addingTimeInterval(horizon)
        }

        // Coordonnées et type (train / bus) de tous les arrêts cités, en quelques requêtes groupées.
        let allStops = Array(Set(relevant.flatMap(\.stopIDs)))
        let points = await ServicePointService.shared.lookup(sloids: allStops)

        return relevant.compactMap { alert -> RailAlert? in
            // On ne garde que ce qui touche le train.
            var seen = Set<String>()
            let trainStops = alert.stopIDs
                .compactMap { points[$0] }
                .filter { $0.isTrain && seen.insert($0.sloid).inserted }
            let isSBBLineAlert = alert.stopIDs.isEmpty && alert.agencyIDs.contains(Self.sbbAgencyID)
            guard !trainStops.isEmpty || isSBBLineAlert else { return nil }

            let stations = RailAlert.orderedAlongLine(trainStops.map {
                Station(id: $0.sloid, name: $0.name, latitude: $0.latitude, longitude: $0.longitude)
            })

            let section: String
            if !alert.header.isEmpty {
                section = alert.header
            } else if let first = stations.first, let last = stations.last, stations.count > 1 {
                section = "\(first.name) – \(last.name)"
            } else {
                section = stations.first?.name ?? t("Perturbation")
            }

            return RailAlert(
                id: "otd-" + alert.id,
                kind: alert.isConstruction ? .construction : .disruption,
                severity: alert.severity,
                section: section,
                details: alert.description.strippingHTML(),
                language: alert.language,
                start: alert.overallStart,
                end: alert.overallEnd,
                window: alert.window,
                link: alert.url.flatMap { URL(string: $0) },
                places: stations,
                cantons: Set(trainStops.compactMap(\.canton)),
                periods: alert.periods
            )
        }
    }
}

// MARK: - Interprétation d'une alerte

private struct RawAlert {
    let id: String
    let header: String
    let description: String
    let url: String?
    let language: String
    let cause: String
    let periods: [DateInterval]
    /// Plage en cours, sinon la prochaine. `nil` si l'alerte n'a pas de période (= toujours active).
    let window: DateInterval?
    let stopIDs: [String]
    let agencyIDs: Set<String>
    /// Titre + description en français, en minuscules (pour le classement).
    let classificationText: String

    init?(id: String, alert: FeedAlert, now: Date) {
        self.id = id
        // Texte affiché : dans la langue choisie dans l'app.
        let headerText = alert.headerText?.preferred
        let descriptionText = alert.descriptionText?.preferred
        header = headerText?.text ?? ""
        description = descriptionText?.text ?? ""
        language = descriptionText?.language ?? headerText?.language ?? "fr"
        url = alert.url?.preferred?.text
        // Classement (travaux, interruption...) : toujours sur le texte français, dont les mots-clés sont testés.
        let frenchHeader = alert.headerText?.text(in: "fr") ?? header
        let frenchDescription = alert.descriptionText?.text(in: "fr") ?? description
        classificationText = (frenchHeader + " " + frenchDescription).lowercased()
        cause = (alert.cause ?? "").uppercased()

        let ranges: [DateInterval] = (alert.activePeriod ?? []).compactMap { range in
            let start = range.start?.value.map { Date(timeIntervalSince1970: $0) } ?? .distantPast
            let end = range.end?.value.map { Date(timeIntervalSince1970: $0) } ?? .distantFuture
            return end >= start ? DateInterval(start: start, end: end) : nil
        }
        periods = ranges
        if ranges.isEmpty {
            window = nil
        } else if let current = ranges.first(where: { $0.contains(now) }) {
            window = current
        } else if let next = ranges.filter({ $0.start > now }).min(by: { $0.start < $1.start }) {
            window = next
        } else {
            return nil // toutes les plages sont passées
        }

        var stops: [String] = []
        for entry in alert.informedEntity ?? [] {
            if let stop = entry.stopId?.value {
                let sloid = Self.normalizeSloid(stop)
                if !stops.contains(sloid) { stops.append(sloid) }
            }
        }
        stopIDs = stops
        agencyIDs = Set((alert.informedEntity ?? []).compactMap { $0.agencyId?.value })

        if header.isEmpty && description.isEmpty { return nil }
    }

    var overallStart: Date? {
        periods.map(\.start).filter { $0 != .distantPast }.min()
    }

    var overallEnd: Date? {
        periods.map(\.end).filter { $0 != .distantFuture }.max()
    }

    private var lowerText: String { classificationText }

    var isConstruction: Bool {
        if cause.contains("CONSTRUCTION") || cause.contains("MAINTENANCE") { return true }
        return ["travaux", "chantier", "bauarbeiten", "construction work"].contains { lowerText.contains($0) }
    }

    var severity: RailAlert.Severity {
        let interrupted = ["interrompu", "interruption", "ne circule pas", "ne circulent pas",
                           "bus de remplacement", "remplacé par des bus", "unterbrochen", "interrupted"]
        if interrupted.contains(where: { lowerText.contains($0) }) { return .interrupted }
        // Simples informations (accessibilité, informations sur un train précis...).
        let information = ["mobilité réduite", "information sur", "n'est pas accessible",
                           "ascenseur", "accès limité"]
        if information.contains(where: { lowerText.contains($0) }) { return .info }
        return .limited
    }

    /// "ch:1:sloid:7000:3:4" (un quai) -> "ch:1:sloid:7000" (la gare).
    static func normalizeSloid(_ id: String) -> String {
        let parts = id.split(separator: ":")
        if parts.count >= 4 && parts[2] == "sloid" {
            return parts.prefix(4).joined(separator: ":")
        }
        return id
    }
}

// MARK: - Format du flux (GTFS-RT en JSON)

private struct FeedMessage: Decodable {
    let entity: [FeedEntity]?
}

private struct FeedEntity: Decodable {
    let id: String?
    let alert: FeedAlert?
}

private struct FeedAlert: Decodable {
    let activePeriod: [FeedTimeRange]?
    let informedEntity: [FeedEntitySelector]?
    let cause: String?
    let url: FeedTranslatedString?
    let headerText: FeedTranslatedString?
    let descriptionText: FeedTranslatedString?
}

private struct FeedTimeRange: Decodable {
    let start: FlexibleNumber?
    let end: FlexibleNumber?
}

private struct FeedEntitySelector: Decodable {
    let agencyId: FlexibleText?
    let stopId: FlexibleText?
}

private struct FeedTranslatedString: Decodable {
    let translation: [Item]?

    struct Item: Decodable {
        let text: String?
        let language: String?
    }

    private var items: [(text: String, language: String)] {
        (translation ?? []).compactMap { item -> (text: String, language: String)? in
            guard let text = item.text, !text.isEmpty else { return nil }
            return (text, (item.language ?? "").lowercased())
        }
    }

    /// Texte dans une langue précise ("fr", "de", "it", "en"), s'il existe.
    func text(in language: String) -> String? {
        items.first { $0.language.hasPrefix(language) }?.text
    }

    /// Version dans la langue choisie dans l'app, sinon français, anglais, allemand.
    var preferred: (text: String, language: String)? {
        for wanted in [AppLanguage.current.rawValue, "fr", "en", "de"] {
            if let match = items.first(where: { $0.language.hasPrefix(wanted) }) {
                return (match.text, wanted)
            }
        }
        return items.first
    }
}

/// Nombre envoyé soit comme nombre, soit comme texte ("1790768220").
private struct FlexibleNumber: Decodable {
    let value: Double?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Double.self) {
            value = number
        } else if let text = try? container.decode(String.self) {
            value = Double(text)
        } else {
            value = nil
        }
    }
}

/// Texte envoyé soit comme texte, soit comme nombre.
private struct FlexibleText: Decodable {
    let value: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            value = text
        } else if let number = try? container.decode(Int.self) {
            value = String(number)
        } else {
            value = nil
        }
    }
}

// MARK: - Arrêts officiels (coordonnées + moyen de transport)

/// Un arrêt du référentiel officiel suisse (jeu de données "Dienststellen" publié par les CFF).
struct ServicePoint: Codable {
    let sloid: String
    let name: String
    let latitude: Double
    let longitude: Double
    let isTrain: Bool
    /// Abréviation du canton ("VD", "BE"...). `nil` pour une gare à l'étranger.
    let canton: String?
}

/// Retrouve les arrêts à partir de leur identifiant "sloid" (ex. "ch:1:sloid:7000" = Bern),
/// par paquets de 80, avec un cache sur le disque.
actor ServicePointService {
    static let shared = ServicePointService()

    private var cache: [String: ServicePoint] = [:]
    private var misses: Set<String> = []
    private let cacheFile: URL?

    init() {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        cacheFile = dir?.appendingPathComponent("service-points-cache-v2.json")
        if let file = cacheFile,
           let data = try? Data(contentsOf: file),
           let saved = try? JSONDecoder().decode([String: ServicePoint].self, from: data) {
            cache = saved
        }
    }

    func lookup(sloids: [String]) async -> [String: ServicePoint] {
        let missing = sloids.filter { cache[$0] == nil && !misses.contains($0) }
        var changed = false

        for chunk in missing.chunked(into: 80) {
            let list = chunk.map { "\"\($0)\"" }.joined(separator: ",")
            guard let url = HTTPClient.url(
                "https://data.sbb.ch/api/explore/v2.1/catalog/datasets/dienststellen-gemass-opentransportdataswiss/records",
                [("where", "sloid in (\(list))"),
                 ("select", "sloid,designationofficial,geopos,meansoftransport,cantonabbreviation"),
                 ("limit", "100")]
            ), let response = try? await HTTPClient.get(url, as: PointsResponse.self) else { continue }

            var found = Set<String>()
            for record in response.results {
                guard let sloid = record.sloid, let name = record.designationofficial,
                      let lat = record.geopos?.lat, let lon = record.geopos?.lon else { continue }
                // Valeurs possibles : "TRAIN", "BUS", "BUS|TRAIN", "RACK_RAILWAY"...
                let modes = (record.meansoftransport ?? "").uppercased()
                cache[sloid] = ServicePoint(sloid: sloid, name: name, latitude: lat, longitude: lon,
                                            isTrain: modes.contains("TRAIN") || modes.contains("RACK_RAILWAY"),
                                            canton: record.cantonabbreviation)
                found.insert(sloid)
                changed = true
            }
            misses.formUnion(Set(chunk).subtracting(found))
        }

        if changed, let file = cacheFile, let data = try? JSONEncoder().encode(cache) {
            try? data.write(to: file, options: .atomic)
        }

        var result: [String: ServicePoint] = [:]
        for sloid in sloids {
            if let point = cache[sloid] { result[sloid] = point }
        }
        return result
    }
}

private struct PointsResponse: Decodable {
    let results: [Point]

    struct Point: Decodable {
        let sloid: String?
        let designationofficial: String?
        let geopos: GeoPos?
        let meansoftransport: String?
        let cantonabbreviation: String?
    }

    struct GeoPos: Decodable {
        let lat: Double?
        let lon: Double?
    }
}
