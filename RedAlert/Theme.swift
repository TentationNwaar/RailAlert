import SwiftUI
import MapKit

/// Couleurs et constantes visuelles de l'app (style sombre, cartes arrondies).
enum Theme {
    static let red = Color(red: 0.94, green: 0.23, blue: 0.21)
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
                    .strokeBorder(.white.opacity(0.08))
            )
    }
}

extension View {
    func cardStyle() -> some View { modifier(CardBackground()) }
}
