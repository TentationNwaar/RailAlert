import SwiftUI
import MapKit
import UIKit

/// Couleurs et constantes visuelles de l'app (style sombre, cartes arrondies).
enum Theme {
    /// Rouge des fonds (boutons, triangles, pastilles). Plus foncé avec « Augmenter le contraste »
    /// pour que le texte blanc posé dessus reste lisible.
    static let red = adaptive(normal: (0.94, 0.23, 0.21), highContrast: (0.80, 0.14, 0.12))
    /// Rouge des textes et icônes posés sur un fond sombre (plus clair, donc plus lisible).
    static let redText = adaptive(normal: (1.00, 0.43, 0.40), highContrast: (1.00, 0.56, 0.52))
    static let yellow = Color(red: 1.00, green: 0.78, blue: 0.10)
    static let green = Color(red: 0.25, green: 0.80, blue: 0.45)
    static let accent = Color(red: 0.36, green: 0.58, blue: 1.00)

    static let background = Color(red: 0.05, green: 0.06, blue: 0.09)
    static let cardTop = Color(red: 0.17, green: 0.22, blue: 0.32)
    static let cardBottom = Color(red: 0.09, green: 0.12, blue: 0.19)

    static var cardGradient: LinearGradient {
        LinearGradient(colors: [cardTop, cardBottom], startPoint: .top, endPoint: .bottom)
    }

    static let cornerRadius: CGFloat = 22

    /// Couleur qui change quand l'option d'accessibilité « Augmenter le contraste » est activée.
    private static func adaptive(normal: (Double, Double, Double), highContrast: (Double, Double, Double)) -> Color {
        Color(UIColor { traits in
            let c = traits.accessibilityContrast == .high ? highContrast : normal
            return UIColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
        })
    }

    static let switzerlandCenter = CLLocationCoordinate2D(latitude: 46.80, longitude: 8.23)
    static let switzerlandRegion = MKCoordinateRegion(
        center: switzerlandCenter,
        span: MKCoordinateSpan(latitudeDelta: 2.6, longitudeDelta: 4.4)
    )

    static func color(for severity: TripReport.Severity) -> Color {
        switch severity {
        case .ok: return green
        case .warning: return yellow
        case .critical: return red
        case .unknown: return .gray
        }
    }
}

/// Fond de carte arrondi réutilisable.
struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(Theme.cardGradient, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(contrast == .increased ? 0.35 : 0.08))
            )
    }

    @Environment(\.colorSchemeContrast) private var contrast
}

extension View {
    func cardStyle() -> some View { modifier(CardBackground()) }
}

// MARK: - Mouvements et accessibilité

/// Animations qui respectent l'option « Réduire les animations » (Réglages > Accessibilité > Mouvement).
enum Motion {
    static var isReduced: Bool { UIAccessibility.isReduceMotionEnabled }

    /// L'animation demandée, ou aucune si l'utilisateur a choisi de réduire les animations.
    static func adaptive(_ animation: Animation) -> Animation? {
        isReduced ? nil : animation
    }
}

extension View {
    /// Zone touchable d'au moins 44 × 44 points (minimum recommandé par Apple).
    func minimumTapTarget() -> some View {
        frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
    }
}
