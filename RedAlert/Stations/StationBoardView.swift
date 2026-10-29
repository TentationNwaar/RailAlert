import SwiftUI

/// Tableau des prochains départs d'une gare (OJP), avec retards, suppressions, voies et affluence.
struct StationBoardView: View {
    let station: Station
    @Environment(\.dismiss) private var dismiss

    @State private var departures: [StationDeparture] = []
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var onlyTrains = true

    private var shown: [StationDeparture] {
        onlyTrains ? departures.filter { $0.mode == "rail" } : departures
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle(t("Trains seulement"), isOn: $onlyTrains)
                }
                if let errorText {
                    Text(errorText).font(.footnote).foregroundStyle(Theme.redText)
                }
                Section {
                    ForEach(shown) { departure in
                        DepartureRow(departure: departure)
                    }
                } footer: {
                    Text(t("Source : opentransportdata.swiss (OJP)"))
                }
            }
            .overlay {
                if isLoading && departures.isEmpty { ProgressView() }
                else if !isLoading && shown.isEmpty && errorText == nil {
                    ContentUnavailableView(t("Aucun départ"), systemImage: "tram")
                }
            }
            .navigationTitle(station.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(t("OK")) { dismiss() }
                }
            }
            .refreshable { await load() }
            .task { await load() }
        }
    }

    private func load() async {
        guard let uic = StationNumber.uic(station.id) else {
            errorText = t("Gare inconnue")
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            departures = try await OJPService.shared.departures(stationID: uic, count: 30)
            errorText = nil
        } catch {
            errorText = t("Horaire indisponible (%@)", error.localizedDescription)
        }
    }
}

/// Une ligne du tableau : heure, ligne, destination, voie, état.
private struct DepartureRow: View {
    let departure: StationDeparture

    private var icon: String {
        switch departure.mode {
        case "bus", "coach": return "bus.fill"
        case "tram": return "tram.fill"
        case "water": return "ferry.fill"
        case "cableway", "telecabin", "funicular": return "cablecar.fill"
        default: return "train.side.front.car"
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Formatting.time(departure.plannedTime))
                    .font(.headline.monospacedDigit())
                    .strikethrough(departure.isCancelled, color: Theme.red)
                if case .delayed(let minutes) = departure.state {
                    Text("+\(minutes)'")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.yellow)
                        .accessibilityLabel(t("%ld min de retard", minutes))
                } else if case .early(let minutes) = departure.state {
                    Text("−\(minutes)'")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.yellow)
                        .accessibilityLabel(t("%ld min d'avance", minutes))
                }
            }
            .frame(minWidth: 54, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Image(systemName: icon).font(.caption).foregroundStyle(.secondary).accessibilityHidden(true)
                    Text(departure.line)
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.red, in: RoundedRectangle(cornerRadius: 4))
                    Text(departure.destination).font(.subheadline).lineLimit(2)
                }
                HStack(spacing: 8) {
                    if departure.isCancelled {
                        Text(t("Supprimé")).font(.caption.weight(.bold)).foregroundStyle(Theme.redText)
                    }
                    if let occupancy = departure.occupancy {
                        OccupancyView(occupancy: occupancy, compact: true)
                    }
                }
            }
            Spacer(minLength: 4)
            if let track = departure.track {
                VStack(spacing: 0) {
                    Text(t("Voie")).font(.caption2).foregroundStyle(.secondary)
                    Text(track)
                        .font(.headline)
                        .foregroundStyle(departure.trackChanged ? Theme.yellow : .primary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(departure.trackChanged ? t("Changement de voie : voie %@", track) : t("Voie %@", track))
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Affluence : 1 à 3 silhouettes, avec le texte si demandé.
struct OccupancyView: View {
    let occupancy: Occupancy
    var compact = false
    /// Taille des silhouettes : suit la taille de texte choisie dans les réglages de l'iPhone.
    @ScaledMetric(relativeTo: .caption) private var iconSize: CGFloat = 9

    private var color: Color {
        switch occupancy {
        case .low: return Theme.green
        case .medium: return Theme.yellow
        case .high: return Theme.red
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            HStack(spacing: 0) {
                ForEach(1...3, id: \.self) { index in
                    Image(systemName: "person.fill")
                        .font(.system(size: iconSize))
                        .foregroundStyle(index <= occupancy.level ? color : Color.white.opacity(0.2))
                }
            }
            if !compact {
                Text(occupancy.label).font(.caption)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(t("Affluence : %@", occupancy.label))
    }
}
