import SwiftUI

/// Premier lancement : choix de la langue de l'app (et des messages officiels).
/// Le titre est écrit dans les 4 langues, puisque la langue n'est pas encore connue.
struct LanguagePickerView: View {
    var onChoose: (AppLanguage) -> Void

    @State private var selected: AppLanguage = AppLanguage.systemDefault
    @State private var appeared = false

    private let titles = [
        "Choisis ta langue",
        "Wähle deine Sprache",
        "Scegli la tua lingua",
        "Choose your language"
    ]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer(minLength: 20)

                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 150)

                VStack(spacing: 6) {
                    ForEach(titles, id: \.self) { title in
                        Text(title)
                            .font(title == titles.first ? Font.title3.weight(.bold) : Font.subheadline)
                            .foregroundStyle(title == titles.first ? Color.white : Color.white.opacity(0.6))
                    }
                }
                .multilineTextAlignment(.center)

                VStack(spacing: 12) {
                    ForEach(AppLanguage.allCases) { language in
                        Button {
                            withAnimation(.spring(response: 0.3)) { selected = language }
                        } label: {
                            HStack {
                                Text(language.nativeName)
                                    .font(.title3.weight(.semibold))
                                Spacer()
                                Image(systemName: selected == language ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(selected == language ? Theme.red : Color.white.opacity(0.4))
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color.white.opacity(selected == language ? 0.14 : 0.06))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(selected == language ? Theme.red : Color.clear, lineWidth: 1.5)
                            )
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white)
                    }
                }

                Spacer(minLength: 10)

                Button {
                    onChoose(selected)
                } label: {
                    Text(Translations.text("Continuer", in: selected))
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Theme.red, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .padding(.bottom, 12)
            }
            .padding(.horizontal, 24)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 20)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) { appeared = true }
        }
    }
}
