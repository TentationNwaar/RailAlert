import Foundation

/// Clés privées. Ce fichier est ignoré par git (voir .gitignore) : ne le publie pas.
enum Secrets {
    /// Clé opentransportdata.swiss pour les perturbations et travaux (produit LA-GTFS-SA).
    static let openTransportDataKey = "eyJvcmciOiI2NDA2NTFhNTIyZmEwNTAwMDEyOWJiZTEiLCJpZCI6IjRmNjk2NTE0MThjYTRmNzc4NjI5YWJhMjVlMTY2ZTQ3IiwiaCI6Im11cm11cjEyOCJ9"

    /// Clé opentransportdata.swiss pour les horaires en temps réel (produit OJP 2.0).
    static let ojpKey = "eyJvcmciOiI2NDA2NTFhNTIyZmEwNTAwMDEyOWJiZTEiLCJpZCI6IjQ0ODc5OGY1YTRjNTQ4NmFhMGNhMDhhNjQ3M2MzYmRmIiwiaCI6Im11cm11cjEyOCJ9"

    /// Adresse du serveur push (dossier Server/), ex. "https://redalert.example.ch". Vide = pas de serveur.
    static let serverURL = ""

    /// Clé partagée entre l'app et le serveur (variable APP_KEY du serveur).
    static let serverAppKey = ""
}
