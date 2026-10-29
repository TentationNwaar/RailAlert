import Foundation
import StoreKit
import WidgetKit

/// Achats intégrés avec StoreKit 2 (le système d'achat d'Apple).
///
/// Deux produits, à créer avec exactement ces identifiants dans App Store Connect
/// (et déjà présents dans RedAlert.storekit pour tester dans Xcode sans compte payant) :
/// - `ch.maxweyermann.RedAlert.plus.monthly` : abonnement mensuel (CHF 3.– par mois) ;
/// - `ch.maxweyermann.RedAlert.plus.lifetime` : achat unique « à vie » (CHF 25.–).
/// Les prix affichés viennent de l'App Store : ils ne sont pas écrits dans le code.
@MainActor
final class StoreManager: ObservableObject {
    static let shared = StoreManager()

    static let monthlyID = "ch.maxweyermann.RedAlert.plus.monthly"
    static let lifetimeID = "ch.maxweyermann.RedAlert.plus.lifetime"

    enum Plan { case monthly, lifetime }

    @Published private(set) var products: [Product] = []
    @Published private(set) var isPremium = Premium.isActive
    @Published private(set) var activePlan: Plan?
    @Published private(set) var isEligibleForTrial = false
    @Published private(set) var isLoadingProducts = false
    @Published private(set) var isPurchasing = false
    @Published var errorMessage: String?

    private var updatesTask: Task<Void, Never>?

    var monthly: Product? { products.first { $0.id == Self.monthlyID } }
    var lifetime: Product? { products.first { $0.id == Self.lifetimeID } }

    private init() {
        // Achats faits ailleurs (autre appareil, renouvellement, remboursement, achat validé plus tard par un parent).
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let transaction) = update {
                    await transaction.finish()
                }
                await self?.refreshEntitlements()
            }
        }
        Task {
            await refreshEntitlements()
            await loadProducts()
        }
    }

    // MARK: Produits

    func loadProducts() async {
        guard products.isEmpty, !isLoadingProducts else { return }
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            let loaded = try await Product.products(for: [Self.monthlyID, Self.lifetimeID])
            products = loaded.sorted { first, _ in first.id == Self.monthlyID }
            if let subscription = monthly?.subscription {
                isEligibleForTrial = await subscription.isEligibleForIntroOffer
            }
        } catch {
            errorMessage = t("Achats indisponibles pour le moment. Réessaie plus tard.")
        }
    }

    /// Durée de l'essai gratuit en jours (nil s'il n'y en a pas ou si l'utilisateur l'a déjà utilisé).
    var trialDays: Int? {
        guard isEligibleForTrial,
              let offer = monthly?.subscription?.introductoryOffer,
              offer.paymentMode == .freeTrial
        else { return nil }
        let period = offer.period
        switch period.unit {
        case .day: return period.value
        case .week: return period.value * 7
        case .month: return period.value * 30
        case .year: return period.value * 365
        @unknown default: return nil
        }
    }

    // MARK: Achat

    /// Achète le produit. Renvoie `true` si Red Alert+ est actif ensuite.
    @discardableResult
    func purchase(_ product: Product) async -> Bool {
        isPurchasing = true
        errorMessage = nil
        defer { isPurchasing = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    errorMessage = t("L'achat n'a pas pu être vérifié.")
                    return false
                }
                await transaction.finish()
                await refreshEntitlements()
            case .pending:
                // Achat à valider (par exemple par un parent avec « Demander l'autorisation »).
                errorMessage = t("Achat en attente de validation.")
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            errorMessage = t("L'achat a échoué (%@).", error.localizedDescription)
        }
        return isPremium
    }

    /// Récupère les achats faits avec le même compte Apple (nouvel iPhone, réinstallation).
    func restore() async {
        errorMessage = nil
        do {
            try await AppStore.sync()
        } catch {
            errorMessage = t("Restauration impossible (%@).", error.localizedDescription)
        }
        await refreshEntitlements()
        if !isPremium && errorMessage == nil {
            errorMessage = t("Aucun achat trouvé pour ce compte Apple.")
        }
    }

    // MARK: Mode test (versions de développement uniquement)

    #if DEBUG
    private static let debugKey = "debug.forcePremium"

    /// Active Red Alert+ sans achat, pour tester. N'existe pas dans les versions TestFlight et App Store.
    static var debugForcePremium: Bool {
        get { UserDefaults.standard.bool(forKey: debugKey) }
        set { UserDefaults.standard.set(newValue, forKey: debugKey) }
    }

    func setDebugPremium(_ on: Bool) async {
        Self.debugForcePremium = on
        await refreshEntitlements()
    }
    #endif

    // MARK: Droits

    /// Recalcule l'accès à partir des achats valides (abonnement en cours ou achat à vie).
    func refreshEntitlements() async {
        var plan: Plan?
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result, transaction.revocationDate == nil else { continue }
            switch transaction.productID {
            case Self.lifetimeID: plan = .lifetime
            case Self.monthlyID where plan == nil: plan = .monthly
            default: break
            }
        }

        var active = plan != nil
        #if DEBUG
        // Mode test (uniquement dans les versions lancées depuis Xcode) : Réglages > Développeur.
        if Self.debugForcePremium { active = true }
        #endif
        let changed = active != isPremium
        activePlan = plan
        isPremium = active
        Premium.setActive(isPremium)

        if changed {
            // Le serveur surveille tous les trajets (Red Alert+) ou plus aucun (version gratuite).
            await ServerSync.sync()
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
