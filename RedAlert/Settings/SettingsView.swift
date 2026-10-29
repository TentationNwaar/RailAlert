import SwiftUI
import UIKit
import UserNotifications
import StoreKit

/// Réglages internes de l'app (non visibles par l'utilisateur).
enum AppSettings {
    /// Clé API opentransportdata.swiss, intégrée à l'app (voir Secrets.swift). Vide = pas de clé.
    static var apiKey: String {
        Secrets.openTransportDataKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Écran "Réglages" destiné aux utilisateurs : langue, notifications, aide, sources.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @AppStorage(AppLanguage.storageKey, store: AppLanguage.store) private var languageCode = AppLanguage.current.rawValue
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @ObservedObject private var store = StoreManager.shared
    @State private var showPaywall = false
    @State private var showManageSubscription = false

    /// Appelé quand l'utilisateur veut revoir le tutoriel.
    var onReplayTutorial: () -> Void = {}

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        Image("Logo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 72)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Red Alert").font(.headline)
                            Text(t("Perturbations et travaux sur le réseau ferroviaire suisse"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    if store.isPremium {
                        HStack {
                            Label(t("Red Alert+ actif"), systemImage: "checkmark.seal.fill")
                                .foregroundStyle(Theme.green)
                            Spacer()
                            Text(store.activePlan == .lifetime ? t("À vie") : (store.activePlan == .monthly ? t("Mensuel") : "Test"))
                                .foregroundStyle(.secondary)
                        }
                        if store.activePlan == .monthly {
                            Button(t("Gérer mon abonnement")) { showManageSubscription = true }
                        }
                    } else {
                        Button {
                            showPaywall = true
                        } label: {
                            Label(t("Découvrir Red Alert+"), systemImage: "star.fill")
                        }
                    }
                    Button(t("Restaurer mes achats")) { Task { await store.restore() } }
                    if let message = store.errorMessage {
                        Text(message).font(.footnote).foregroundStyle(Theme.yellow)
                    }
                } header: {
                    Text("Red Alert+")
                } footer: {
                    Text(t("La version gratuite surveille 1 trajet. Red Alert+ débloque les trajets illimités, le suivi en direct, les alternatives et la ponctualité."))
                }

                Section {
                    Picker(selection: $languageCode) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.nativeName).tag(language.rawValue)
                        }
                    } label: {
                        Label(t("Langue"), systemImage: "globe")
                    }
                } footer: {
                    Text(t("Les messages officiels sont affichés dans cette langue."))
                }

                Section {
                    HStack {
                        Label(t("Notifications"), systemImage: "bell.badge.fill")
                        Spacer()
                        Text(statusText)
                            .foregroundStyle(notificationStatus == .denied ? Theme.redText : .secondary)
                    }
                    switch notificationStatus {
                    case .notDetermined:
                        Button(t("Autoriser les notifications")) {
                            Task {
                                _ = await TripMonitor.requestAuthorization()
                                await loadStatus()
                            }
                        }
                    case .denied:
                        Button(t("Ouvrir les réglages de l'iPhone")) {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }
                    default:
                        EmptyView()
                    }
                } header: {
                    Text(t("Alertes"))
                } footer: {
                    Text(t("Red Alert t'avertit quand un de tes trajets (onglet « Mes trajets ») est en retard, supprimé, ou touché par une perturbation ou des travaux. Le seuil de retard se règle dans chaque trajet."))
                }

                #if DEBUG
                // Visible uniquement quand l'app est lancée depuis Xcode (jamais sur l'App Store).
                Section {
                    Toggle("Simuler Red Alert+", isOn: Binding(
                        get: { StoreManager.debugForcePremium },
                        set: { on in Task { await store.setDebugPremium(on) } }
                    ))
                } header: {
                    Text(verbatim: "Développeur")
                } footer: {
                    Text(verbatim: "Active toutes les fonctions payantes sans achat. Cette section n'existe pas dans la version publiée.")
                }
                #endif

                Section(t("Aide")) {
                    Button {
                        onReplayTutorial()
                    } label: {
                        Label(t("Revoir le tutoriel"), systemImage: "questionmark.bubble.fill")
                    }
                }

                Section {
                    NavigationLink {
                        PrivacyPolicyView()
                    } label: {
                        Label(t("Politique de confidentialité"), systemImage: "hand.raised.fill")
                    }
                } header: {
                    Text(t("Confidentialité"))
                } footer: {
                    Text(t("Tes trajets restent sur ton iPhone. Aucune publicité, aucun suivi."))
                }

                Section {
                    sourceRow(t("Perturbations et travaux"), "opentransportdata.swiss")
                    sourceRow(t("Retards et suppressions"), "opentransportdata.swiss")
                    sourceRow(t("Recherche de gares"), "transport.opendata.ch")
                    sourceRow(t("Gares et cantons"), "data.sbb.ch")
                } header: {
                    Text(t("Sources des données"))
                } footer: {
                    Text(t("Données ouvertes des transports publics suisses. Red Alert n'est pas une application officielle des CFF : en cas de doute, vérifie sur sbb.ch ou l'app CFF."))
                }

                Section {
                    HStack {
                        Text(t("Version"))
                        Spacer()
                        Text(version).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(t("Réglages"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(t("OK")) { dismiss() }
                }
            }
            .task { await loadStatus() }
            .sheet(isPresented: $showPaywall) { PaywallView() }
            .manageSubscriptionsSheet(isPresented: $showManageSubscription)
        }
    }

    private var statusText: String {
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral: return t("Activées")
        case .denied: return t("Désactivées")
        default: return t("Pas encore demandées")
        }
    }

    private func loadStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationStatus = settings.authorizationStatus
    }

    private func sourceRow(_ title: String, _ source: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(source).font(.footnote).foregroundStyle(.secondary)
        }
    }
}
