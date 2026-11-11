import Foundation

/// ─────────────────────────────────────────────────────────────
///  À COMPLÉTER : tes informations pour la politique de confidentialité.
///  Elles apparaissent dans Réglages → Confidentialité, dans les 4 langues.
///  Tant qu'un champ est vide, l'app affiche « [à compléter] ».
/// ─────────────────────────────────────────────────────────────
enum LegalInfo {
    /// Prénom et nom du responsable (toi).
    static let ownerName = "Maxence Weyermann"

    /// Ville (ou adresse postale), sans « Suisse » : il est ajouté automatiquement.
    static let ownerAddress = "Lausanne"

    /// Adresse e-mail de contact pour les questions sur les données.
    static let contactEmail = "bubbleblack_@hotmail.com"

    /// Hébergeur du serveur de notifications et pays du centre de données
    /// (exemple : « Infomaniak, Suisse »). Laisser vide tant que le serveur n'est pas en ligne.
    static let serverHost = ""

    /// Date de la dernière mise à jour de la politique (exemple : « 1er octobre 2026 »).
    static let lastUpdated = "30 septembre 2026"

    /// Adresse web de la politique publiée (exigée par Apple pour l'App Store). Optionnel dans l'app.
    static let privacyPolicyURL = "https://tentationnwaar.github.io/redalert-site/privacy.html"
}
