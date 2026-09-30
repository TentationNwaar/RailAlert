import Foundation

/// Langues proposées dans l'app. Le romanche n'est pas proposé : les messages officiels
/// des transports publics n'existent pas dans cette langue.
enum AppLanguage: String, CaseIterable, Codable, Identifiable {
    case fr, de, it, en

    var id: String { rawValue }

    /// Nom de la langue dans la langue elle-même.
    var nativeName: String {
        switch self {
        case .fr: return "Français"
        case .de: return "Deutsch"
        case .it: return "Italiano"
        case .en: return "English"
        }
    }

    /// Paramètres régionaux utilisés pour les dates (ex. "mer. 30 sept." / "Mi., 30. Sept.").
    var locale: Locale {
        switch self {
        case .fr: return Locale(identifier: "fr_CH")
        case .de: return Locale(identifier: "de_CH")
        case .it: return Locale(identifier: "it_CH")
        case .en: return Locale(identifier: "en_GB")
        }
    }

    // MARK: Langue choisie (partagée entre l'app, le widget et les notifications)

    static let storageKey = "appLanguage"
    static let store: UserDefaults = UserDefaults(suiteName: AppConfig.appGroupID) ?? .standard

    /// L'utilisateur a-t-il déjà choisi sa langue (premier lancement) ?
    static var hasChosen: Bool {
        AppLanguage(rawValue: store.string(forKey: storageKey) ?? "") != nil
    }

    /// Langue choisie, sinon celle de l'iPhone si elle est proposée, sinon le français.
    static var current: AppLanguage {
        if let raw = store.string(forKey: storageKey), let language = AppLanguage(rawValue: raw) {
            return language
        }
        return systemDefault
    }

    static var systemDefault: AppLanguage {
        for identifier in Locale.preferredLanguages {
            if let language = AppLanguage(rawValue: String(identifier.prefix(2))) { return language }
        }
        return .fr
    }
}

/// Traduit un texte écrit en français dans la langue choisie.
/// Les `%@` (texte) et `%ld` (nombre) sont remplacés par les valeurs données.
///
///     t("Mis à jour à %@", "09:23")  // "Aktualisiert um 09:23" en allemand
func t(_ french: String, _ arguments: CVarArg...) -> String {
    let language = AppLanguage.current
    let template = Translations.text(french, in: language)
    guard !arguments.isEmpty else { return template }
    return String(format: template, locale: language.locale, arguments: arguments)
}
