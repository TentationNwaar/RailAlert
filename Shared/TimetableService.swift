import Foundation

/// Horaire en temps réel des trajets : uniquement OJP 2.0 (source officielle, voir OJPService).
///
/// L'ancienne source de secours (search.ch) a été retirée : ses conditions d'utilisation
/// interdisent l'accès automatisé et l'usage commercial, ce qui bloquerait la publication sur l'App Store.
struct TimetableService {
    static let shared = TimetableService()

    /// Liste des correspondances entre deux gares à partir d'une date.
    func connections(from: Station, to: Station, at date: Date, count: Int = 5) async throws -> [ConnectionInfo] {
        guard OJPService.shared.isAvailable else { throw APIError.missingKey }
        return try await OJPService.shared.connections(fromID: from.id, toID: to.id, at: date, count: count)
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
