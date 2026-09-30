import Foundation

/// Recherche de gares et géolocalisation via transport.opendata.ch (sans clé API).
/// Doc : https://transport.opendata.ch/docs.html
actor StationService {
    static let shared = StationService()

    /// Cache nom -> gare, conservé sur le disque pour éviter de refaire les mêmes requêtes.
    private var cache: [String: Station] = [:]
    /// Noms introuvables, pour ne pas les redemander à chaque rafraîchissement.
    private var misses: Set<String> = []
    private let cacheFile: URL?

    init() {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        cacheFile = dir?.appendingPathComponent("stations-cache.json")
        if let file = cacheFile,
           let data = try? Data(contentsOf: file),
           let saved = try? JSONDecoder().decode([String: Station].self, from: data) {
            cache = saved
        }
    }

    /// Autocomplétion : liste de gares correspondant au texte tapé.
    func search(_ query: String) async throws -> [Station] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }
        guard let url = HTTPClient.url("https://transport.opendata.ch/v1/locations",
                                       [("query", trimmed), ("type", "station")])
        else { throw APIError.invalidURL }
        let response = try await HTTPClient.get(url, as: LocationsResponse.self)
        return response.stations.compactMap(\.station)
    }

    /// Trouve les coordonnées d'une gare à partir de son nom (résultat mis en cache).
    func lookup(name: String) async -> Station? {
        let key = name.lowercased()
        if let cached = cache[key] { return cached }
        if misses.contains(key) { return nil }
        guard let first = try? await search(name).first else {
            misses.insert(key)
            return nil
        }
        cache[key] = first
        persist()
        return first
    }

    private func persist() {
        guard let file = cacheFile, let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: file, options: .atomic)
    }
}

// MARK: - Format de réponse de transport.opendata.ch

private struct LocationsResponse: Decodable {
    let stations: [Location]

    struct Location: Decodable {
        let id: String?
        let name: String?
        let coordinate: Coordinate?

        /// Attention : dans cette API, x = latitude et y = longitude.
        var station: Station? {
            guard let id, let name, let lat = coordinate?.x, let lon = coordinate?.y else { return nil }
            return Station(id: id, name: name, latitude: lat, longitude: lon)
        }
    }

    struct Coordinate: Decodable {
        let x: Double?
        let y: Double?
    }
}
