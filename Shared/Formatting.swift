import Foundation

/// Formats d'affichage (heures, retards) en heure suisse.
enum Formatting {
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_CH")
        f.timeZone = AppConfig.swissTimeZone
        f.dateFormat = "HH:mm"
        return f
    }()

    /// Un format "jour + heure" par langue (ex. "mer. 30 sept., 20:30" / "Mi., 30. Sept., 20:30").
    private static let dayTimeFormatters: [AppLanguage: DateFormatter] = {
        var result: [AppLanguage: DateFormatter] = [:]
        for language in AppLanguage.allCases {
            let f = DateFormatter()
            f.locale = language.locale
            f.timeZone = AppConfig.swissTimeZone
            f.setLocalizedDateFormatFromTemplate("EEEdMMMHHmm")
            result[language] = f
        }
        return result
    }()

    static func time(_ date: Date) -> String { timeFormatter.string(from: date) }

    static func dayTime(_ date: Date) -> String {
        (dayTimeFormatters[AppLanguage.current] ?? timeFormatter).string(from: date)
    }

    /// "À l'heure", "+4 min", "Supprimé", "—"
    static func stateText(_ state: DepartureState) -> String {
        switch state {
        case .onTime: return t("À l'heure")
        case .delayed(let minutes): return t("+%ld min", minutes)
        case .cancelled: return t("Supprimé")
        case .unknown: return t("Pas d'info temps réel")
        }
    }

    /// Version courte pour le widget : "OK", "+4'", "Supprimé"
    static func shortStateText(_ state: DepartureState) -> String {
        switch state {
        case .onTime: return "OK"
        case .delayed(let minutes): return "+\(minutes)'"
        case .cancelled: return t("Supprimé")
        case .unknown: return "—"
        }
    }

    /// Nom de symbole SF Symbols pour un état.
    static func symbol(for severity: TripReport.Severity) -> String {
        switch severity {
        case .ok: return "checkmark.circle.fill"
        case .warning: return "clock.badge.exclamationmark.fill"
        case .critical: return "xmark.octagon.fill"
        case .unknown: return "questionmark.circle"
        }
    }
}
