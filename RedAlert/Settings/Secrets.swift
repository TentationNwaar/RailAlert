import Foundation

/// Clés privées. Ce fichier est ignoré par git (voir .gitignore) : ne le publie pas.
enum Secrets {
    /// Clé opentransportdata.swiss (application "RedAlert", abonnement LA-GTFS-SA).
    /// Utilisée si aucune autre clé n'est saisie dans les réglages de l'app.
    static let openTransportDataKey = "eyJvcmciOiI2NDA2NTFhNTIyZmEwNTAwMDEyOWJiZTEiLCJpZCI6IjRmNjk2NTE0MThjYTRmNzc4NjI5YWJhMjVlMTY2ZTQ3IiwiaCI6Im11cm11cjEyOCJ9"
}
