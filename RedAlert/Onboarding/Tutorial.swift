import SwiftUI
import UserNotifications

// MARK: - Déroulé du tutoriel

/// Pilote le tutoriel à bulles : étape en cours, onglet affiché, position des boutons à mettre en évidence.
@MainActor
final class TutorialController: ObservableObject {
    enum Tab: Hashable { case map, trips }

    /// Éléments de l'interface qu'une bulle peut mettre en évidence.
    enum Target: Hashable { case list, filters, settings }

    enum Step: Int, CaseIterable {
        case welcome, markers, filters, list, settings, lockScreen, trips

        var title: String {
            switch self {
            case .welcome: return t("Bienvenue sur Red Alert")
            case .markers: return t("La carte")
            case .filters: return t("Filtres")
            case .list: return t("Liste des alertes")
            case .settings: return t("Réglages")
            case .trips: return t("Tes trajets")
            case .lockScreen: return t("Sur l'écran verrouillé")
            }
        }

        var text: String {
            switch self {
            case .welcome: return t("Red Alert surveille le réseau ferroviaire suisse et te prévient quand tes trajets sont touchés.")
            case .markers: return t("Chaque triangle est une alerte : rouge = plus aucun train, jaune = service restreint. Le marteau indique des travaux. Touche un triangle pour zoomer et lire le détail.")
            case .filters: return t("Choisis ce que tu veux voir (perturbations, travaux) et ta région. Tes choix sont gardés.")
            case .list: return t("Toutes les alertes affichées, sous forme de liste. Touche-en une pour la voir sur la carte.")
            case .settings: return t("Langue, notifications et sources des données. Tu peux aussi relancer ce tutoriel d'ici.")
            case .trips: return t("Ajoute les trajets que tu fais souvent, avec ton heure habituelle. Red Alert surveille le train, les perturbations et les travaux sur tout le parcours.")
            case .lockScreen: return t("Autorise les notifications pour être prévenu, et ajoute le widget « Mon trajet » à ton écran verrouillé pour voir l'état de ton train d'un coup d'œil.")
            }
        }

        /// Élément mis en évidence (nil = bulle centrée).
        var target: Target? {
            switch self {
            case .filters: return .filters
            case .list: return .list
            case .settings: return .settings
            default: return nil
            }
        }

        var tab: Tab { self == .trips ? .trips : .map }

        var isLast: Bool { self == Step.allCases.last }
    }

    @Published var step: Step?
    @Published var selectedTab: Tab = .map
    /// Position à l'écran des éléments à mettre en évidence (mise à jour par `.tutorialTarget`).
    @Published var frames: [Target: CGRect] = [:]
    /// Demande à l'onglet Trajets d'ouvrir le formulaire d'ajout (bouton "Ajouter mon premier trajet").
    @Published var requestAddTrip = false

    static let completedKey = "onboarding.completed"

    static var isCompleted: Bool { UserDefaults.standard.bool(forKey: completedKey) }

    func start() {
        selectedTab = .map
        withAnimation(.easeInOut(duration: 0.3)) { step = .welcome }
    }

    func next() {
        guard let step else { return }
        guard let following = Step(rawValue: step.rawValue + 1) else {
            finish()
            return
        }
        withAnimation(.easeInOut(duration: 0.3)) {
            selectedTab = following.tab
            self.step = following
        }
    }

    func previous() {
        guard let step, let before = Step(rawValue: step.rawValue - 1) else { return }
        withAnimation(.easeInOut(duration: 0.3)) {
            selectedTab = before.tab
            self.step = before
        }
    }

    func finish() {
        withAnimation(.easeInOut(duration: 0.3)) { step = nil }
        UserDefaults.standard.set(true, forKey: Self.completedKey)
    }
}

// MARK: - Repérage des éléments à mettre en évidence

extension View {
    /// Enregistre la position de cette vue pour que le tutoriel puisse l'entourer.
    func tutorialTarget(_ target: TutorialController.Target) -> some View {
        modifier(TutorialTargetModifier(target: target))
    }
}

private struct TutorialTargetModifier: ViewModifier {
    @EnvironmentObject private var tutorial: TutorialController
    let target: TutorialController.Target

    func body(content: Content) -> some View {
        content.background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { tutorial.frames[target] = geo.frame(in: .global) }
                    .onChange(of: geo.frame(in: .global)) { _, frame in
                        tutorial.frames[target] = frame
                    }
            }
        )
    }
}

// MARK: - Affichage des bulles

/// Couche posée au-dessus de toute l'app pendant le tutoriel :
/// fond assombri, élément mis en évidence (découpe + anneau qui pulse) et bulle explicative.
struct TutorialOverlay: View {
    @EnvironmentObject private var tutorial: TutorialController
    @State private var pulse = false

    var body: some View {
        if let step = tutorial.step {
            GeometryReader { proxy in
                let hole = step.target
                    .flatMap { tutorial.frames[$0] }
                    .map { $0.insetBy(dx: -8, dy: -8) }

                ZStack {
                    // Fond assombri avec une "fenêtre" autour de l'élément mis en évidence.
                    Rectangle()
                        .fill(Color.black.opacity(0.72))
                        .mask {
                            ZStack {
                                Rectangle()
                                if let hole {
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .frame(width: hole.width, height: hole.height)
                                        .position(x: hole.midX, y: hole.midY)
                                        .blendMode(.destinationOut)
                                }
                            }
                            .compositingGroup()
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { } // bloque les touches sur l'app pendant le tutoriel

                    if let hole {
                        // Anneau qui pulse + zone touchable : toucher l'élément fait avancer le tutoriel.
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Theme.red, lineWidth: 3)
                            .frame(width: hole.width, height: hole.height)
                            .scaleEffect(pulse ? 1.12 : 1)
                            .opacity(pulse ? 0.3 : 1)
                            .position(x: hole.midX, y: hole.midY)
                        Color.clear
                            .frame(width: hole.width, height: hole.height)
                            .contentShape(Rectangle())
                            .position(x: hole.midX, y: hole.midY)
                            .onTapGesture { tutorial.next() }
                    }

                    bubbleLayout(step: step, hole: hole, size: proxy.size)
                }
            }
            .ignoresSafeArea()
            .transition(.opacity)
            .onAppear {
                withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) { pulse = true }
            }
        }
    }

    /// Place la bulle sous l'élément s'il est en haut de l'écran, au-dessus sinon, au centre s'il n'y en a pas.
    @ViewBuilder
    private func bubbleLayout(step: TutorialController.Step, hole: CGRect?, size: CGSize) -> some View {
        let bubble = TutorialBubble(step: step, pointsToTarget: hole != nil)
            .frame(maxWidth: 380)
            .padding(.horizontal, 20)
            .id(step)
            .transition(.scale(scale: 0.92).combined(with: .opacity))

        if let hole {
            if hole.midY < size.height / 2 {
                VStack(spacing: 0) {
                    Spacer().frame(height: hole.maxY + 14)
                    bubble
                    Spacer(minLength: 0)
                }
            } else {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    bubble
                    Spacer().frame(height: size.height - hole.minY + 14)
                }
            }
        } else {
            VStack {
                Spacer()
                bubble
                Spacer()
            }
        }
    }
}

/// La bulle elle-même : titre, texte, contenu propre à l'étape, navigation.
private struct TutorialBubble: View {
    @EnvironmentObject private var tutorial: TutorialController
    let step: TutorialController.Step
    let pointsToTarget: Bool

    @State private var notificationsOn = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if step == .welcome {
                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120)
                    .frame(maxWidth: .infinity)
            }

            Text(step.title)
                .font(.title3.bold())
            Text(step.text)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)

            extraContent

            if pointsToTarget {
                Label(t("Touche la zone éclairée pour continuer"), systemImage: "hand.tap.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Navigation : points d'étape, Passer, Suivant / Terminer.
            HStack(spacing: 12) {
                HStack(spacing: 5) {
                    ForEach(TutorialController.Step.allCases, id: \.self) { item in
                        Circle()
                            .fill(item == step ? Theme.red : Color.white.opacity(0.3))
                            .frame(width: 6, height: 6)
                    }
                }
                Spacer()
                if !step.isLast {
                    Button(t("Passer")) { tutorial.finish() }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Button {
                    tutorial.next()
                } label: {
                    Text(step == .welcome ? t("Commencer") : (step.isLast ? t("Terminer") : t("Suivant")))
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Theme.red, in: Capsule())
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .background(Theme.cardGradient, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.white.opacity(0.1))
        )
        .shadow(color: .black.opacity(0.5), radius: 20, y: 8)
        .task {
            if step == .lockScreen {
                let settings = await UNUserNotificationCenter.current().notificationSettings()
                notificationsOn = settings.authorizationStatus == .authorized
            }
        }
    }

    /// Contenu interactif propre à certaines étapes.
    @ViewBuilder
    private var extraContent: some View {
        switch step {
        case .markers:
            // Légende des triangles.
            HStack(spacing: 16) {
                legend(color: Theme.red, symbol: "exclamationmark", text: t("Interrompu"))
                legend(color: Theme.yellow, symbol: "exclamationmark", text: t("Restreint"))
                legend(color: Theme.yellow, symbol: "hammer.fill", text: t("Travaux"))
            }
        case .trips:
            Button {
                // Termine le tutoriel et ouvre directement le formulaire d'ajout.
                tutorial.finish()
                tutorial.requestAddTrip = true
            } label: {
                Label(t("Ajouter mon premier trajet"), systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        case .lockScreen:
            // Aperçu du widget d'écran verrouillé.
            HStack(spacing: 10) {
                Image(systemName: "clock.badge.exclamationmark.fill").font(.title2)
                VStack(alignment: .leading, spacing: 1) {
                    Text(t("+%ld min", 4)).font(.headline)
                    Text("Montreux → Lausanne").font(.caption)
                    Text("07:23 · IR 95 · 1").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))

            Button {
                Task {
                    notificationsOn = await TripMonitor.requestAuthorization()
                }
            } label: {
                Label(notificationsOn ? t("Notifications activées") : t("Activer les notifications"),
                      systemImage: notificationsOn ? "checkmark.circle.fill" : "bell.badge.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .disabled(notificationsOn)
        default:
            EmptyView()
        }
    }

    private func legend(color: Color, symbol: String, text: String) -> some View {
        VStack(spacing: 4) {
            ZStack {
                Image(systemName: "triangle.fill").font(.system(size: 24)).foregroundStyle(color)
                Image(systemName: symbol)
                    .font(.system(size: symbol == "hammer.fill" ? 9 : 11, weight: .black))
                    .foregroundStyle(.black)
                    .offset(y: 2)
            }
            Text(text).font(.caption2)
        }
    }
}
