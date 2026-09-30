import Foundation
import Translation

/// Charge les perturbations et les travaux, les traduit si besoin et les garde à jour.
@MainActor
final class AlertMapModel: ObservableObject {
    @Published private(set) var alerts: [RailAlert] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastUpdate: Date?
    @Published private(set) var source: DisruptionService.Source = .sbb
    /// Filtres choisis par l'utilisateur (enregistrés à chaque changement).
    @Published var filters: AlertFilters = AlertFilters.load() {
        didSet { filters.save() }
    }

    // MARK: Traduction automatique dans la langue choisie (faite sur l'iPhone)

    /// Quand cette configuration change, SwiftUI lance une session de traduction (voir `.translationTask`).
    @Published var translationConfiguration: TranslationSession.Configuration?
    @Published private(set) var translations: [String: String] = [:]

    /// Dernière requête : sert à respecter la limite de requêtes d'opentransportdata.swiss.
    private var lastAttempt: Date?

    // MARK: Listes affichées

    /// Alertes qui passent les filtres (liste).
    var visibleAlerts: [RailAlert] {
        let now = Date()
        return alerts.filter { filters.accepts($0, now: now) }
    }

    /// Alertes placées sur la carte (gares retrouvées). Les simples informations restent dans la liste.
    var mappedAlerts: [RailAlert] { visibleAlerts.filter { $0.isOnMap && $0.severity != .info } }

    /// Alertes avec au moins deux gares : on trace le tronçon.
    var sectionAlerts: [RailAlert] { mappedAlerts.filter { $0.places.count >= 2 } }

    var interruptedCount: Int { visibleAlerts.filter { $0.severity == .interrupted }.count }

    /// Nombre d'alertes qu'afficheraient d'autres filtres (pour l'aperçu dans la feuille Filtres).
    func count(with filters: AlertFilters) -> Int {
        let now = Date()
        return alerts.filter { filters.accepts($0, now: now) }.count
    }

    /// Les travaux ne sont disponibles qu'avec la source opentransportdata.swiss.
    var constructionAvailable: Bool { source == .openTransportData }

    /// Texte à afficher : la traduction française si elle existe, sinon l'original.
    func displayText(for alert: RailAlert) -> String {
        translations[alert.details] ?? alert.details
    }

    func isTranslated(_ alert: RailAlert) -> Bool {
        alert.needsTranslation && translations[alert.details] != nil
    }

    // MARK: Chargement

    func refresh(force: Bool = false) async {
        guard !isLoading else { return }
        // Avec la clé API : au maximum une requête toutes les 31 s.
        if !AppSettings.apiKey.isEmpty, !force, let last = lastAttempt, Date().timeIntervalSince(last) < 31 {
            return
        }
        lastAttempt = .now
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await AlertCache.shared.result(maxAge: force ? 60 : 240)
            alerts = result.alerts
            source = result.source
            lastUpdate = .now
            errorMessage = result.warning
            requestTranslationIfNeeded()
        } catch {
            errorMessage = t("Impossible de charger les perturbations. %@", error.localizedDescription)
        }
    }

    /// Rafraîchit tant que la carte est affichée : toutes les 2 min (data.sbb.ch)
    /// ou toutes les 5 min avec la clé (le flux complet pèse environ 1 Mo).
    func autoRefresh() async {
        while !Task.isCancelled {
            await refresh(force: true)
            let minutes: UInt64 = AppSettings.apiKey.isEmpty ? 2 : 5
            try? await Task.sleep(nanoseconds: minutes * 60 * 1_000_000_000)
        }
    }

    // MARK: Traduction

    private var pendingTexts: [String] {
        Array(Set(alerts.filter(\.needsTranslation).map(\.details).filter { translations[$0] == nil }))
    }

    private func requestTranslationIfNeeded() {
        guard !pendingTexts.isEmpty else { return }
        if translationConfiguration == nil {
            // Langue source détectée automatiquement, langue cible = celle choisie dans l'app.
            translationConfiguration = TranslationSession.Configuration(
                source: nil,
                target: Locale.Language(identifier: AppLanguage.current.rawValue)
            )
        } else {
            // Relance une session avec la même configuration.
            translationConfiguration?.invalidate()
        }
    }

    /// Appelé par `.translationTask` avec une session prête.
    /// La première fois, iOS peut demander de télécharger la langue française.
    func translate(using session: TranslationSession) async {
        let texts = pendingTexts
        guard !texts.isEmpty else { return }
        let requests = texts.enumerated().map { index, text in
            TranslationSession.Request(sourceText: text, clientIdentifier: String(index))
        }
        do {
            let responses = try await session.translations(from: requests)
            for response in responses {
                guard let id = response.clientIdentifier, let index = Int(id), index < texts.count else { continue }
                translations[texts[index]] = response.targetText
            }
        } catch {
            // Traduction indisponible (simulateur, langue non téléchargée...) : on garde l'anglais.
            print("Traduction impossible : \(error.localizedDescription)")
        }
    }
}
