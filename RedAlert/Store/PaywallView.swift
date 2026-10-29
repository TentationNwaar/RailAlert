import SwiftUI
import StoreKit

/// Écran « Red Alert+ » : avantages, choix entre l'abonnement mensuel et l'achat à vie.
struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @ObservedObject private var store = StoreManager.shared
    @State private var selectedID = StoreManager.monthlyID

    /// Contrat de licence standard d'Apple (utilisable tel quel pour les abonnements).
    private let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    header
                    benefits

                    if store.isPremium {
                        Label(t("Red Alert+ est actif. Merci !"), systemImage: "checkmark.seal.fill")
                            .font(.headline)
                            .foregroundStyle(Theme.green)
                    } else if store.products.isEmpty {
                        unavailable
                    } else {
                        options
                        buyButton
                        legalText
                    }

                    if let message = store.errorMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(Theme.yellow)
                            .multilineTextAlignment(.center)
                    }

                    footerLinks
                }
                .padding(20)
            }
            .background(Theme.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("Fermer")) { dismiss() }
                }
            }
            .task { await store.loadProducts() }
        }
    }

    // MARK: Parties de l'écran

    private var header: some View {
        VStack(spacing: 8) {
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(width: 96)
                .accessibilityHidden(true)
            Text("Red Alert+")
                .font(.largeTitle.bold())
            Text(t("Ne rate plus jamais ton train."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var benefits: some View {
        VStack(alignment: .leading, spacing: 12) {
            benefit("infinity", t("Trajets illimités"), t("La version gratuite surveille 1 trajet."))
            if ServerSync.isConfigured {
                benefit("bell.badge.fill", t("Alertes à la minute"), t("Même quand l'app est fermée."))
            }
            benefit("dot.radiowaves.left.and.right", t("Suivi en direct"), t("Sur l'écran verrouillé et dans la Dynamic Island."))
            benefit("arrow.triangle.branch", t("Alternatives"), t("Un autre train proposé quand le tien a un problème."))
            benefit("chart.bar.fill", t("Ponctualité"), t("L'historique de ton train sur 30 jours."))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var options: some View {
        VStack(spacing: 10) {
            if let monthly = store.monthly {
                OptionCard(title: t("Mensuel"),
                           price: t("%@ / mois", monthly.displayPrice),
                           note: store.trialDays.map { t("%ld jours gratuits, puis résiliable à tout moment", $0) }
                                ?? t("Résiliable à tout moment"),
                           isSelected: selectedID == monthly.id) { selectedID = monthly.id }
            }
            if let lifetime = store.lifetime {
                OptionCard(title: t("À vie"),
                           price: lifetime.displayPrice,
                           note: t("Paiement unique, sans abonnement"),
                           isSelected: selectedID == lifetime.id) { selectedID = lifetime.id }
            }
        }
    }

    private var buyButton: some View {
        Button {
            guard let product = store.products.first(where: { $0.id == selectedID }) else { return }
            Task {
                if await store.purchase(product) { dismiss() }
            }
        } label: {
            Group {
                if store.isPurchasing {
                    ProgressView().tint(.white)
                } else {
                    Text(buttonTitle).font(.headline)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Theme.red, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .disabled(store.isPurchasing)
    }

    private var buttonTitle: String {
        if selectedID == StoreManager.monthlyID, let days = store.trialDays {
            return t("Essayer gratuitement %ld jours", days)
        }
        return t("Continuer")
    }

    /// Mentions demandées par Apple pour un abonnement.
    private var legalText: some View {
        Text(t("L'abonnement mensuel est renouvelé automatiquement et payé via ton compte Apple. Tu peux le résilier à tout moment dans Réglages > ton nom > Abonnements, au plus tard 24 h avant le renouvellement."))
            .font(.caption2)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
    }

    private var unavailable: some View {
        VStack(spacing: 10) {
            if store.isLoadingProducts {
                ProgressView()
            } else {
                Text(t("Achats indisponibles pour le moment. Réessaie plus tard."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button(t("Réessayer")) { Task { await store.loadProducts() } }
            }
        }
    }

    private var footerLinks: some View {
        VStack(spacing: 12) {
            Button(t("Restaurer mes achats")) { Task { await store.restore() } }
                .font(.subheadline)
            HStack(spacing: 18) {
                Button(t("Conditions d'utilisation")) { openURL(termsURL) }
                NavigationLink(t("Confidentialité")) { PrivacyPolicyView() }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func benefit(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.red)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Une option d'achat (mensuel ou à vie), sélectionnable.
private struct OptionCard: View {
    let title: String
    let price: String
    let note: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Theme.red : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(note).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(price).font(.headline)
            }
            .padding(14)
            .background(.white.opacity(isSelected ? 0.12 : 0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isSelected ? Theme.red : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Bandeau « Red Alert+ » réutilisable

/// Petit encart qui remplace une fonction réservée à Red Alert+ et ouvre l'écran d'achat.
struct PremiumLockedCard: View {
    let title: String
    let text: String
    @State private var showPaywall = false

    var body: some View {
        Button {
            showPaywall = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "lock.fill")
                    .foregroundStyle(Theme.red)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.semibold))
                    Text(text).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("Red Alert+")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.red, in: Capsule())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showPaywall) { PaywallView() }
    }
}
