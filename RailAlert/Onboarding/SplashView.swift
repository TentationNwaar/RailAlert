import SwiftUI

/// Écran de démarrage animé :
/// 1. le logo apparaît en fondu ;
/// 2. un petit train rouge traverse l'écran très vite, de gauche à droite, en traçant une ligne droite ;
/// 3. l'écran s'ouvre en deux le long de cette ligne (haut vers le haut, bas vers le bas) et laisse voir l'app.
struct SplashView: View {
    var onFinish: () -> Void

    @State private var logoVisible = false
    @State private var trainProgress: CGFloat = 0   // 0 = hors écran à gauche, 1 = hors écran à droite
    @State private var lineOpacity: Double = 1
    @State private var isSplit = false

    /// Hauteur de la ligne de séparation (en proportion de l'écran).
    private let lineRatio: CGFloat = 0.56

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let lineY = size.height * lineRatio

            ZStack(alignment: .topLeading) {
                // Moitié haute : contient le logo, part vers le haut.
                panel(size: size, lineY: lineY)
                    .mask(alignment: .top) {
                        Rectangle().frame(height: lineY)
                    }
                    .offset(y: isSplit ? -lineY : 0)

                // Moitié basse : part vers le bas.
                panel(size: size, lineY: lineY)
                    .mask(alignment: .bottom) {
                        Rectangle().frame(height: size.height - lineY)
                    }
                    .offset(y: isSplit ? size.height - lineY : 0)

                // Ligne tracée par le train.
                let trainX = -90 + (size.width + 180) * trainProgress
                Rectangle()
                    .fill(Theme.red)
                    .frame(width: max(0, min(size.width, trainX)), height: 3)
                    .shadow(color: Theme.red.opacity(0.9), radius: 6)
                    .position(x: max(0, min(size.width, trainX)) / 2, y: lineY)
                    .opacity(lineOpacity)

                // Le train, posé sur la ligne.
                SplashTrain()
                    .frame(width: 78, height: 26)
                    .position(x: trainX, y: lineY - 13)
                    .opacity(lineOpacity)
            }
            .frame(width: size.width, height: size.height)
        }
        .ignoresSafeArea()
        .allowsHitTesting(!isSplit)
        // Toucher l'écran passe l'animation.
        .contentShape(Rectangle())
        .onTapGesture { finish() }
        // Animation décorative : VoiceOver annonce seulement le nom de l'app.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rail Alert")
        .task { await play() }
    }

    /// Fond noir + logo (le même dessin est utilisé pour les deux moitiés).
    private func panel(size: CGSize, lineY: CGFloat) -> some View {
        ZStack {
            Color.black
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(width: min(size.width * 0.62, 280))
                .opacity(logoVisible ? 1 : 0)
                .scaleEffect(logoVisible ? 1 : 0.9)
                .position(x: size.width / 2, y: lineY - 110)
        }
        .frame(width: size.width, height: size.height)
    }

    @State private var finished = false

    private func finish() {
        guard !finished else { return }
        finished = true
        onFinish()
    }

    /// Durée totale : environ 1,7 s (0,4 s avec « Réduire les animations »).
    private func play() async {
        // « Réduire les animations » : simple fondu, sans train ni ouverture.
        if Motion.isReduced {
            lineOpacity = 0
            withAnimation(.easeOut(duration: 0.25)) { logoVisible = true }
            try? await Task.sleep(nanoseconds: 400_000_000)
            finish()
            return
        }

        // 1. Logo en fondu.
        withAnimation(.easeOut(duration: 0.45)) { logoVisible = true }
        try? await Task.sleep(nanoseconds: 550_000_000)
        guard !finished else { return }

        // 2. Le train traverse l'écran (rapide, avec une accélération au départ).
        withAnimation(.easeIn(duration: 0.45)) { trainProgress = 1 }
        try? await Task.sleep(nanoseconds: 480_000_000)
        guard !finished else { return }

        // 3. Ouverture en deux.
        withAnimation(.easeInOut(duration: 0.5)) {
            isSplit = true
            lineOpacity = 0
        }
        try? await Task.sleep(nanoseconds: 520_000_000)
        finish()
    }
}

/// Petit train rouge vu de profil, qui roule vers la droite, avec des traits de vitesse.
private struct SplashTrain: View {
    var body: some View {
        ZStack(alignment: .leading) {
            // Traits de vitesse derrière le train.
            VStack(alignment: .trailing, spacing: 5) {
                Capsule().frame(width: 26, height: 2)
                Capsule().frame(width: 18, height: 2)
                Capsule().frame(width: 30, height: 2)
            }
            .foregroundStyle(Theme.red.opacity(0.6))
            .offset(x: -30)

            TrainBody()
                .fill(Theme.red)
                .overlay(
                    // Fenêtres.
                    HStack(spacing: 4) {
                        ForEach(0..<4, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 1.5).fill(Color.black).frame(width: 8, height: 6)
                        }
                    }
                    .offset(x: -6, y: -2)
                )
        }
    }
}

/// Silhouette de la locomotive : corps rectangulaire, nez arrondi à droite.
private struct TrainBody: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let noseStart = rect.maxX - rect.height * 0.9
        path.move(to: CGPoint(x: rect.minX + 3, y: rect.minY))
        path.addLine(to: CGPoint(x: noseStart, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY - 3),
                          control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + 3))
        path.addQuadCurve(to: CGPoint(x: rect.minX + 3, y: rect.minY),
                          control: CGPoint(x: rect.minX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
