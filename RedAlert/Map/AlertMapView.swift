import SwiftUI
import MapKit
import Translation

/// Écran principal : carte de la Suisse avec les perturbations et les travaux (triangles jaunes / rouges).
struct AlertMapView: View {
    @StateObject private var model = AlertMapModel()
    @EnvironmentObject private var tutorial: TutorialController
    @State private var position: MapCameraPosition = .region(Theme.switzerlandRegion)
    @State private var selected: RailAlert?
    @State private var showList = false
    @State private var showSettings = false
    @State private var showFilters = false

    var body: some View {
        ZStack {
            map

            VStack(spacing: 10) {
                header
                filterBar
                Spacer()
                if let selected {
                    AlertDetailCard(alert: selected,
                                    details: model.displayText(for: selected),
                                    isTranslated: model.isTranslated(selected)) { deselect() }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if let error = model.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .cardStyle()
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .task {
            position = .region(homeRegion)
            await model.autoRefresh()
        }
        // Traduction automatique des textes anglais (data.sbb.ch) en français.
        .translationTask(model.translationConfiguration) { session in
            await model.translate(using: session)
        }
        .sheet(isPresented: $showList) {
            AlertListView(alerts: model.visibleAlerts) { alert in
                showList = false
                select(alert)
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showSettings) {
            SettingsView {
                // "Revoir le tutoriel" : on ferme les réglages, puis on relance les bulles.
                showSettings = false
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    tutorial.start()
                }
            }
        }
        .sheet(isPresented: $showFilters) {
            AlertFilterView(model: model)
                .presentationDetents([.medium, .large])
        }
        .onChange(of: model.filters) { oldValue, newValue in
            if let selected, !model.visibleAlerts.contains(where: { $0.id == selected.id }) {
                self.selected = nil
            }
            // Zoom sur les régions choisies.
            if oldValue.regions != newValue.regions {
                withAnimation(.easeInOut(duration: 0.8)) {
                    position = .region(homeRegion)
                }
            }
        }
    }

    // MARK: Carte

    private var map: some View {
        Map(position: $position) {
            // Tronçons touchés (pointillés colorés).
            ForEach(model.sectionAlerts) { alert in
                MapPolyline(coordinates: alert.places.map(\.coordinate))
                    .stroke(alert.severity.color.opacity(alert.isActiveNow ? 0.85 : 0.4),
                            style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round,
                                               dash: alert.kind == .construction ? [2, 7] : [8, 6]))
            }

            // Gares aux extrémités des tronçons.
            ForEach(model.sectionAlerts) { alert in
                ForEach(endpoints(of: alert)) { place in
                    Annotation(place.name, coordinate: place.coordinate, anchor: .center) {
                        Circle()
                            .fill(.white)
                            .frame(width: 9, height: 9)
                            .overlay(Circle().stroke(alert.severity.color, lineWidth: 3))
                    }
                }
            }

            // Triangles d'alerte.
            ForEach(model.mappedAlerts) { alert in
                Annotation(alert.section, coordinate: alert.coordinate, anchor: .center) {
                    AlertMarker(severity: alert.severity, kind: alert.kind, isSelected: selected?.id == alert.id)
                        .opacity(alert.isActiveNow || selected?.id == alert.id ? 1 : 0.55)
                        .onTapGesture { select(alert) }
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .mapControls {
            MapCompass()
            MapScaleView()
        }
    }

    /// Première et dernière gare d'un tronçon.
    private func endpoints(of alert: RailAlert) -> [Station] {
        guard let first = alert.places.first, let last = alert.places.last else { return [] }
        return first.id == last.id ? [first] : [first, last]
    }

    // MARK: En-tête

    private var header: some View {
        HStack(spacing: 10) {
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(width: 58)
            VStack(alignment: .leading, spacing: 2) {
                Text("Red Alert")
                    .font(.title2.bold())
                HStack(spacing: 6) {
                    if model.isLoading {
                        ProgressView().controlSize(.mini)
                    } else {
                        Circle()
                            .fill(model.interruptedCount > 0 ? Theme.red : (model.alerts.isEmpty ? Theme.green : Theme.yellow))
                            .frame(width: 8, height: 8)
                    }
                    Text(statusText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            CircleButton(systemImage: "list.bullet") { showList = true }
                .tutorialTarget(.list)
            CircleButton(systemImage: "line.3.horizontal.decrease") { showFilters = true }
                .tutorialTarget(.filters)
                .overlay(alignment: .topTrailing) {
                    // Point bleu : des filtres personnalisés sont actifs.
                    if !model.filters.isDefault {
                        Circle().fill(Theme.accent).frame(width: 10, height: 10).offset(x: 1, y: -1)
                    }
                }
            CircleButton(systemImage: "gearshape.fill") { showSettings = true }
                .tutorialTarget(.settings)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .padding(.top, 4)
    }

    private var statusText: String {
        if model.isLoading && model.lastUpdate == nil { return t("Chargement…") }
        let count = model.visibleAlerts.count
        let what: String
        switch count {
        case 0: what = t("Rien à signaler")
        case 1: what = t("1 alerte")
        default: what = t("%ld alertes", count)
        }
        if let date = model.lastUpdate { return "\(what) · \(Formatting.time(date))" }
        return what
    }

    // MARK: Filtres

    /// Résumé des filtres actifs ; un tap ouvre la feuille Filtres.
    private var filterBar: some View {
        HStack {
            Button { showFilters = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal.decrease.circle.fill")
                    Text(model.filters.summary)
                        .lineLimit(1)
                }
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(.ultraThinMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
        }
    }

    /// Vue d'ensemble : les régions choisies, sinon toute la Suisse.
    private var homeRegion: MKCoordinateRegion {
        SwissRegion.mapRegion(for: model.filters.regions) ?? Theme.switzerlandRegion
    }

    // MARK: Sélection

    private func select(_ alert: RailAlert) {
        withAnimation(.easeInOut(duration: 0.8)) {
            selected = alert
            position = .region(alert.isOnMap ? alert.region : homeRegion)
        }
    }

    private func deselect() {
        withAnimation(.easeInOut(duration: 0.8)) {
            selected = nil
            position = .region(homeRegion)
        }
    }
}

// MARK: - Triangle d'alerte

struct AlertMarker: View {
    let severity: RailAlert.Severity
    let kind: RailAlert.Kind
    let isSelected: Bool
    @State private var pulse = false

    var body: some View {
        ZStack {
            // Onde qui pulse pour les interruptions imprévues (rouge).
            if severity == .interrupted && kind == .disruption {
                Circle()
                    .fill(severity.color.opacity(0.4))
                    .frame(width: 46, height: 46)
                    .scaleEffect(pulse ? 1.35 : 0.6)
                    .opacity(pulse ? 0 : 0.9)
            }
            Image(systemName: "triangle.fill")
                .font(.system(size: isSelected ? 40 : 28))
                .foregroundStyle(severity.color)
                .shadow(color: .black.opacity(0.55), radius: 3, y: 2)
            Image(systemName: kind.symbol)
                .font(.system(size: symbolSize, weight: .black))
                .foregroundStyle(.black)
                .offset(y: isSelected ? 4 : 3)
        }
        .frame(width: 52, height: 52)
        .contentShape(Rectangle())
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isSelected)
        .onAppear {
            withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { pulse = true }
        }
    }

    private var symbolSize: CGFloat {
        switch (kind, isSelected) {
        case (.construction, true): return 14
        case (.construction, false): return 10
        case (.disruption, true): return 17
        case (.disruption, false): return 12
        }
    }
}

// MARK: - Fiche détaillée d'une alerte

struct AlertDetailCard: View {
    let alert: RailAlert
    let details: String
    let isTranslated: Bool
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Label(alert.headline,
                          systemImage: alert.kind == .construction ? "hammer.fill" : "exclamationmark.triangle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(alert.severity.color)
                    Text(alert.section)
                        .font(.title3.bold())
                        .lineLimit(3)
                    if let window = alert.windowText {
                        Text(window)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(alert.isActiveNow ? alert.severity.color : Color.white.opacity(0.8))
                    }
                    Text(alert.periodText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.body.weight(.bold))
                        .frame(width: 34, height: 34)
                        .background(.white.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
            }

            if !details.isEmpty {
                ScrollView {
                    Text(details)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 160)
                .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                if let link = alert.link {
                    Link(destination: link) {
                        Label(t("Voir la source"), systemImage: "arrow.up.right.square")
                            .font(.subheadline.weight(.semibold))
                    }
                }
                Spacer()
                if isTranslated {
                    Label(t("Traduit automatiquement"), systemImage: "character.bubble")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .cardStyle()
    }
}

// MARK: - Liste de toutes les alertes

struct AlertListView: View {
    let alerts: [RailAlert]
    var onSelect: (RailAlert) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if alerts.isEmpty {
                    ContentUnavailableView(t("Rien à signaler"),
                                           systemImage: "checkmark.seal",
                                           description: Text(t("Aucune perturbation ni aucun travail en cours dans cette catégorie.")))
                } else {
                    List(alerts) { alert in
                        Button { onSelect(alert) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: alert.kind == .construction ? "hammer.fill" : "exclamationmark.triangle.fill")
                                    .foregroundStyle(alert.severity.color)
                                    .font(.title3)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(alert.section).font(.headline).lineLimit(2)
                                    Text(alert.headline + (alert.isOnMap ? "" : t(" · non localisé")))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(alert.windowText ?? alert.periodText)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle(t("Alertes"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Bouton rond

struct CircleButton: View {
    let systemImage: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .frame(width: 38, height: 38)
                .background(.white.opacity(0.12), in: Circle())
        }
        .buttonStyle(.plain)
    }
}
