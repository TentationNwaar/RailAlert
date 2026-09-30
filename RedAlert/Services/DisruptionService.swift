import Foundation

/// Source sans clé API : messages de perturbation publiés par les CFF sur data.sbb.ch
/// (mis à jour toutes les 5 min, textes en anglais uniquement, pas de travaux).
/// Jeu de données : https://data.sbb.ch/explore/dataset/rail-traffic-information/
///
/// Chaque message a un titre du type "Interrupted service: Vevey - Villeneuve VD".
/// On en déduit la gravité (type 1 = interrompu, 2 = restreint, 5 = rétabli)
/// et les gares concernées, que l'on géolocalise ensuite.
///
/// Attention : les dates sont en heure suisse, mais marquées "+00:00" (UTC) par erreur.
/// On ignore donc ce suffixe et on les lit comme heure de Zurich.
struct SBBRailInfoSource {
    func fetchAlerts(now: Date = .now) async throws -> [RailAlert] {
        guard let url = HTTPClient.url(
            "https://data.sbb.ch/api/explore/v2.1/catalog/datasets/rail-traffic-information/records",
            // Marge d'un jour à cause du décalage horaire ; le tri fin est fait ci-dessous.
            [("where", "enddatetime > now(days=-1)"),
             ("order_by", "published desc"),
             ("limit", "100")]
        ) else { throw APIError.invalidURL }

        let response = try await HTTPClient.get(url, as: RecordsResponse.self)

        // Un même incident a plusieurs messages (début, mise à jour, "Service resumed").
        // On les regroupe par numéro et on garde le plus récent.
        var latest: [String: Record] = [:]
        for record in response.results {
            let key = record.messageID
            if let existing = latest[key], (existing.publishedDate ?? .distantPast) >= (record.publishedDate ?? .distantPast) {
                continue
            }
            latest[key] = record
        }

        // On retire les incidents terminés.
        let active = latest.values.filter { record in
            !record.isResolved && (record.endDate ?? .distantFuture) > now
        }

        // Géolocalisation des gares (en parallèle, avec cache).
        let names = Set(active.flatMap { $0.parsedTitle.places })
        var located: [String: Station] = [:]
        await withTaskGroup(of: (String, Station?).self) { group in
            for name in names {
                group.addTask {
                    let station = await StationService.shared.lookup(name: name)
                    return (name, station)
                }
            }
            for await (name, station) in group {
                if let station { located[name] = station }
            }
        }

        return active.map { record in
            let parsed = record.parsedTitle
            return RailAlert(
                id: "sbb-" + record.messageID,
                kind: .disruption,
                severity: record.severity,
                section: parsed.places.isEmpty ? parsed.rest : parsed.places.joined(separator: " – "),
                details: record.cleanDetails,
                language: "en",
                start: record.startDate,
                end: record.endDate,
                window: Self.window(record.startDate, record.endDate),
                link: record.link.flatMap { URL(string: $0) },
                places: parsed.places.compactMap { located[$0] }
            )
        }
    }
}

extension SBBRailInfoSource {
    static func window(_ start: Date?, _ end: Date?) -> DateInterval? {
        guard let start, let end, end >= start else { return nil }
        return DateInterval(start: start, end: end)
    }
}

// MARK: - Format de réponse de data.sbb.ch

private struct RecordsResponse: Decodable {
    let results: [Record]
}

private struct Record: Decodable {
    let title: String?
    let link: String?
    let description: String?
    let description_html: String?
    let published: String?
    let startdatetime: String?
    let enddatetime: String?
    let type: String?

    /// Lit "2026-09-30T08:56:00+00:00" comme 08:56 heure suisse (voir remarque plus haut).
    private static let localParser: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = AppConfig.swissTimeZone
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f
    }()

    private static func parse(_ text: String?) -> Date? {
        guard let text, text.count >= 19 else { return nil }
        return localParser.date(from: String(text.prefix(19)))
    }

    var publishedDate: Date? { Self.parse(published) }
    var startDate: Date? { Self.parse(startdatetime) }
    var endDate: Date? { Self.parse(enddatetime) }

    /// Numéro du message = fin du lien sbb.ch (".../1251190").
    var messageID: String {
        if let link, let last = link.split(separator: "/").last { return String(last) }
        return title ?? UUID().uuidString
    }

    var isResolved: Bool {
        type == "5" || (title ?? "").lowercased().hasPrefix("service resumed")
    }

    var severity: RailAlert.Severity {
        let lower = (title ?? "").lowercased()
        if type == "1" || lower.hasPrefix("interrupted") { return .interrupted }
        if type == "2" || lower.hasPrefix("limited") { return .limited }
        return .info
    }

    /// Texte sans la ligne de dates du début ("30.09.2026 08:56 - 12:00"), déjà affichée ailleurs.
    var cleanDetails: String {
        let text = (description_html ?? description ?? "").strippingHTML()
        let pattern = #"^\d{2}\.\d{2}\.\d{4} \d{2}:\d{2}( - (\d{2}\.\d{2}\.\d{4} )?\d{2}:\d{2})?\s*"#
        return text.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// "Limited service: Lausanne - Fribourg/Freiburg" -> ["Lausanne", "Fribourg/Freiburg"]
    var parsedTitle: (rest: String, places: [String]) {
        let full = title ?? ""
        guard let colon = full.range(of: ": ") else { return (full, []) }
        let rest = String(full[colon.upperBound...]).trimmingCharacters(in: .whitespaces)
        let places = rest
            .components(separatedBy: " - ")
            .flatMap { $0.components(separatedBy: " and ") }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return (rest, places)
    }
}
