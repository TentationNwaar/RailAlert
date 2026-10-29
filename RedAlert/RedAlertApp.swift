import SwiftUI
import UIKit
import WidgetKit
import UserNotifications

@main
struct RedAlertApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var trips = TripsModel()
    /// Démarré dès le lancement pour ne manquer aucun achat ou renouvellement.
    private let store = StoreManager.shared

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environmentObject(trips)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                // En quittant l'app : on programme la prochaine vérification en arrière-plan.
                BackgroundRefresh.schedule()
                WidgetCenter.shared.reloadAllTimelines()
            case .active:
                Task { await trips.refreshAll() }
            default:
                break
            }
        }
        // Tâche lancée par iOS en arrière-plan (quand le système le décide).
        .backgroundTask(.appRefresh(AppConfig.backgroundRefreshID)) {
            BackgroundRefresh.schedule()
            await TripMonitor.checkAll()
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}

/// Ce qui s'affiche au lancement :
/// splash animé → choix de la langue (premier lancement) → tutoriel à bulles (premier lancement) → app.
struct AppRootView: View {
    @AppStorage(AppLanguage.storageKey, store: AppLanguage.store) private var languageCode = ""
    @StateObject private var tutorial = TutorialController()
    @State private var showSplash = true
    @State private var needsLanguage = !AppLanguage.hasChosen

    var body: some View {
        ZStack {
            // L'app. Quand la langue change, tout est redessiné dans la nouvelle langue.
            RootView()
                .id(languageCode)

            // Bulles du tutoriel, au-dessus de l'app (y compris la barre d'onglets).
            TutorialOverlay()
                .zIndex(1)

            // Premier lancement : choix de la langue (visible dès que le splash s'ouvre).
            if needsLanguage {
                LanguagePickerView { language in
                    languageCode = language.rawValue
                    withAnimation(.easeInOut(duration: 0.4)) { needsLanguage = false }
                    if !TutorialController.isCompleted {
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 600_000_000)
                            tutorial.start()
                        }
                    }
                }
                .transition(.opacity)
                .zIndex(2)
            }

            if showSplash {
                SplashView {
                    showSplash = false
                    if !needsLanguage && !TutorialController.isCompleted { tutorial.start() }
                }
                .zIndex(3)
            }
        }
        .environmentObject(tutorial)
        // Lien redalert://trip/… (widget, suivi en direct).
        .onOpenURL { AppRouter.shared.handle($0) }
        .onChange(of: languageCode) { _, _ in
            WidgetCenter.shared.reloadAllTimelines()
            // Le serveur envoie les notifications dans la langue choisie.
            Task { await ServerSync.sync() }
        }
    }
}

/// Barre d'onglets : Carte / Trajets.
struct RootView: View {
    @EnvironmentObject private var tutorial: TutorialController
    @ObservedObject private var router = AppRouter.shared

    var body: some View {
        // « Mes trajets » d'abord : c'est l'écran qui intéresse le plus au quotidien.
        TabView(selection: $tutorial.selectedTab) {
            TripsView()
                .tabItem { Label(t("Mes trajets"), systemImage: "tram.fill") }
                .tag(TutorialController.Tab.trips)
            AlertMapView()
                .tabItem { Label(t("Carte"), systemImage: "map.fill") }
                .tag(TutorialController.Tab.map)
        }
        // Un trajet doit s'ouvrir (notification, widget) : on passe sur l'onglet Trajets.
        .onChange(of: router.pendingTripID, initial: true) { _, id in
            if id != nil { tutorial.selectedTab = .trips }
        }
    }
}

/// Délégué de l'app : permet d'afficher les notifications même quand l'app est ouverte.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        // Serveur push (si configuré dans Secrets.swift) : demande d'un jeton à Apple.
        ServerSync.registerForPushIfConfigured()
        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        ServerSync.setDeviceToken(deviceToken)
        Task { await ServerSync.sync() }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Normal tant que la capacité "Push Notifications" n'est pas activée (compte Apple Developer payant).
        print("Push : \(error.localizedDescription)")
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    /// Notification touchée : on ouvre le trajet concerné.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        if let raw = (info["tripID"] ?? info["tripId"]) as? String, let id = UUID(uuidString: raw) {
            Task { @MainActor in AppRouter.shared.openTrip(id) }
        }
        completionHandler()
    }
}
