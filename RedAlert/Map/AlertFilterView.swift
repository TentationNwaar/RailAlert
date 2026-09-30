import SwiftUI

/// Feuille "Filtres" : quelles alertes afficher et dans quelle région.
/// Les changements s'appliquent tout de suite à la carte.
struct AlertFilterView: View {
    @ObservedObject var model: AlertMapModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(isOn: $model.filters.showDisruptions) {
                        Label(t("Perturbations"), systemImage: "exclamationmark.triangle.fill")
                    }
                    Toggle(isOn: $model.filters.showConstruction.animation()) {
                        Label(t("Travaux"), systemImage: "hammer.fill")
                    }
                    .disabled(!model.constructionAvailable)

                    if model.filters.showConstruction && model.constructionAvailable {
                        Picker(t("Travaux à afficher"), selection: $model.filters.constructionHorizon) {
                            ForEach(AlertFilters.ConstructionHorizon.allCases) { horizon in
                                Text(horizon.label).tag(horizon)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                } header: {
                    Text(t("Types d'alertes"))
                } footer: {
                    if !model.constructionAvailable {
                        Text(t("Les travaux sont momentanément indisponibles."))
                    }
                }

                Section {
                    Toggle(isOn: $model.filters.onlyInterruptions) {
                        Label {
                            Text(t("Seulement les interruptions"))
                        } icon: {
                            Image(systemName: "triangle.fill").foregroundStyle(Theme.red)
                        }
                    }
                    Toggle(isOn: $model.filters.showInformation) {
                        Label(t("Informations diverses"), systemImage: "info.circle")
                    }
                } header: {
                    Text(t("Gravité"))
                } footer: {
                    Text(t("Interruption : plus aucun train ne circule sur le tronçon (triangle rouge). Les informations diverses (accessibilité des gares, informations sur un train précis) apparaissent seulement dans la liste."))
                }

                Section {
                    regionRow(title: t("Toute la Suisse"), subtitle: nil, isOn: model.filters.regions.isEmpty) {
                        model.filters.regions = []
                    }
                    ForEach(SwissRegion.allCases) { region in
                        regionRow(title: region.name,
                                  subtitle: region.cantonsText,
                                  isOn: model.filters.regions.contains(region)) {
                            if model.filters.regions.contains(region) {
                                model.filters.regions.remove(region)
                            } else {
                                model.filters.regions.insert(region)
                            }
                        }
                    }
                } header: {
                    Text(t("Région"))
                } footer: {
                    Text(t("Tu peux choisir plusieurs régions. La carte zoome automatiquement dessus."))
                }

                if !model.filters.isDefault {
                    Section {
                        Button(t("Réinitialiser les filtres")) {
                            withAnimation { model.filters = .default }
                        }
                    }
                }
            }
            .navigationTitle(t("Filtres"))
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                Text(countText)
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 8)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(t("OK")) { dismiss() }
                }
            }
        }
    }

    private var countText: String {
        let count = model.visibleAlerts.count
        switch count {
        case 0: return t("Aucune alerte avec ces filtres")
        case 1: return t("1 alerte affichée")
        default: return t("%ld alertes affichées", count)
        }
    }

    private func regionRow(title: String, subtitle: String?, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: { withAnimation { action() } }) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(.primary)
                    if let subtitle {
                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if isOn {
                    Image(systemName: "checkmark").foregroundStyle(Theme.accent).fontWeight(.semibold)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
