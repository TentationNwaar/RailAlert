import SwiftUI
import UIKit
import UserNotifications

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
                            .foregroundStyle(notificationStatus == .denied ? Theme.red : .secondary)
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

                Section(t("Aide")) {
                    Button {
                        onReplayTutorial()
                    } label: {
                        Label(t("Revoir le tutoriel"), systemImage: "questionmark.bubble.fill")
                    }
                }

                Section {
                    sourceRow(t("Perturbations et travaux"), "opentransportdata.swiss")
                    sourceRow(t("Retards et suppressions"), "search.ch")
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
