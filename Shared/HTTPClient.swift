import Foundation

/// Petit client HTTP commun à tous les services.
enum HTTPClient {
    static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    /// Construit une URL avec des paramètres (les caractères spéciaux sont encodés).
    static func url(_ base: String, _ query: [(String, String)]) -> URL? {
        var components = URLComponents(string: base)
        components?.queryItems = query.map { URLQueryItem(name: $0.0, value: $0.1) }
        return components?.url
    }

    /// Télécharge et décode du JSON.
    static func get<T: Decodable>(_ url: URL, as type: T.Type, headers: [String: String] = [:]) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue("RedAlert-iOS/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.badStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.unexpectedFormat
        }
    }
}

enum APIError: LocalizedError {
    case badStatus(Int)
    case invalidURL
    case unexpectedFormat
    case missingKey

    var errorDescription: String? {
        switch self {
        case .badStatus(let code) where code == 401 || code == 403: return t("Accès aux données refusé (code %ld).", code)
        case .badStatus(429): return t("Trop de requêtes. Réessaie dans une minute.")
        case .badStatus(let code): return t("Le serveur a répondu avec le code %ld.", code)
        case .invalidURL: return t("Adresse de requête invalide.")
        case .unexpectedFormat: return t("Réponse du serveur dans un format inattendu.")
        case .missingKey: return t("Horaire indisponible pour le moment.")
        }
    }
}

/// Valeur JSON quelconque : sert à lire des champs dont le format n'est pas documenté.
enum JSONValue: Decodable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    /// Récupère récursivement les textes associés à certaines clés (ex. "header", "lead").
    func texts(forKeys keys: Set<String>) -> [String] {
        switch self {
        case .array(let values):
            return values.flatMap { $0.texts(forKeys: keys) }
        case .object(let dict):
            var result: [String] = []
            for (key, value) in dict.sorted(by: { $0.key < $1.key }) {
                if keys.contains(key), let text = value.stringValue, !text.isEmpty {
                    result.append(text)
                } else {
                    result.append(contentsOf: value.texts(forKeys: keys))
                }
            }
            return result
        default:
            return []
        }
    }
}

// MARK: - Accès pratiques pour lire un JSON "libre"

extension JSONValue {
    subscript(key: String) -> JSONValue? {
        if case .object(let dict) = self { return dict[key] }
        return nil
    }

    /// Première clé trouvée parmi plusieurs variantes (ex. "headerText" ou "header_text").
    func value(_ keys: String...) -> JSONValue? {
        for key in keys {
            if let found = self[key] { return found }
        }
        return nil
    }

    /// Tous les textes contenus, à n'importe quelle profondeur.
    var allStrings: [String] {
        switch self {
        case .string(let s): return [s]
        case .array(let values): return values.flatMap(\.allStrings)
        case .object(let dict): return dict.values.flatMap(\.allStrings)
        default: return []
        }
    }

    var arrayValue: [JSONValue] {
        if case .array(let values) = self { return values }
        return []
    }

    /// Texte, y compris pour un nombre (ex. un identifiant envoyé comme nombre).
    var textValue: String? {
        switch self {
        case .string(let s): return s
        case .number(let n): return n == n.rounded() ? String(Int64(n)) : String(n)
        case .bool(let b): return String(b)
        default: return nil
        }
    }

    /// Nombre, y compris quand il est envoyé comme texte ("1727690000").
    var doubleValue: Double? {
        switch self {
        case .number(let n): return n
        case .string(let s): return Double(s)
        default: return nil
        }
    }
}

extension Array {
    /// Découpe un tableau en paquets de taille fixe.
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
