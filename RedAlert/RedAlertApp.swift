import SwiftUI
import UIKit
import WidgetKit
import UserNotifications

@main
struct RedAlertApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var trips = TripsModel()

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
        .onChange(of: languageCode) { _, _ in
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}

/// Barre d'onglets : Carte / Trajets.
struct RootView: View {
    @EnvironmentObject private var tutorial: TutorialController

    var body: some View {
        TabView(selection: $tutorial.selectedTab) {
            AlertMapView()
                .tabItem { Label(t("Carte"), systemImage: "map.fill") }
                .tag(TutorialController.Tab.map)
            TripsView()
                .tabItem { Label(t("Mes trajets"), systemImage: "tram.fill") }
                .tag(TutorialController.Tab.trips)
        }
    }
}

/// Délégué de l'app : permet d'afficher les notifications même quand l'app est ouverte.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }
}
