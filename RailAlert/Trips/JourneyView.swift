import SwiftUI

/// Trajet complet, étape par étape : chaque train, bus ou tram, avec heures, retards, voies et correspondances.
/// Évite d'ouvrir une autre app pour voir où changer et si la correspondance tient.
struct JourneyView: View {
    let connection: ConnectionInfo

    private var legs: [TripLeg] { connection.legs ?? [] }
    private var risks: [Int: TransferRisk] {
        Dictionary(uniqueKeysWithValues: connection.transferRisks.map { ($0.nextLegIndex, $0) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(t("Trajet complet")).font(.headline).accessibilityAddTraits(.isHeader)
                Spacer()
                Text(connection.transfers == 0
                     ? t("Direct")
                     : (connection.transfers == 1 ? t("1 changement") : t("%ld changements", connection.transfers)))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            ForEach(Array(legs.enumerated()), id: \.element.id) { index, leg in
                if index > 0 {
                    TransferRow(station: leg.fromName,
                                walkMinutes: leg.walkMinutesBefore,
                                availableMinutes: availableMinutes(before: index),
                                risk: risks[index])
                }
                LegRow(leg: leg)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    /// Temps estimé entre l'arrivée de l'étape précédente et le départ de celle-ci.
    private func availableMinutes(before index: Int) -> Int {
        let previous = legs[index - 1], next = legs[index]
        return Int((next.expectedDeparture.timeIntervalSince(previous.expectedArrival) / 60).rounded(.down))
    }
}

// MARK: - Une étape

private struct LegRow: View {
    let leg: TripLeg

    private var icon: String {
        if leg.isReplacementBus { return "bus.fill" }
        switch leg.mode {
        case "bus", "coach": return "bus.fill"
        case "tram": return "tram.fill"
        case "metro", "underground": return "tram.fill.tunnel"
        case "water": return "ferry.fill"
        case "cableway", "telecabin", "funicular": return "cablecar.fill"
        default: return "train.side.front.car"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Ligne verticale de l'étape.
            VStack(spacing: 2) {
                Circle().fill(Theme.red).frame(width: 9, height: 9)
                Rectangle().fill(Theme.red.opacity(0.6)).frame(width: 3)
                Circle().stroke(Theme.red, lineWidth: 2).frame(width: 9, height: 9)
            }
            .padding(.top, 5)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 8) {
                StopLine(time: leg.plannedDeparture, expected: leg.expectedDeparture,
                         hasRealtime: leg.departureDelay != nil, isCancelled: leg.isCancelled,
                         station: leg.fromName, track: leg.departureTrack,
                         trackChanged: leg.departureTrackChanged, mode: leg.mode)

                HStack(spacing: 6) {
                    Image(systemName: icon).font(.caption).foregroundStyle(.secondary).accessibilityHidden(true)
                    if let line = leg.line {
                        Text(line)
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.red, in: RoundedRectangle(cornerRadius: 4))
                    }
                    if let destination = leg.destination {
                        Text(t("direction %@", destination))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                if leg.isCancelled {
                    Label(t("Supprimé"), systemImage: "xmark.octagon.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.redText)
                } else if leg.isReplacementBus {
                    Label(t("Bus de remplacement"), systemImage: "bus.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.yellow)
                } else if case .early(let minutes) = leg.departureState {
                    Label(t("%ld min d'avance", minutes), systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.yellow)
                }

                StopLine(time: leg.plannedArrival, expected: leg.expectedArrival,
                         hasRealtime: leg.arrivalDelay != nil, isCancelled: leg.isCancelled,
                         station: leg.toName, track: leg.arrivalTrack,
                         trackChanged: false, mode: leg.mode)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// « 16:08 → 16:09  Montreux        Voie 1 »
private struct StopLine: View {
    let time: Date
    let expected: Date
    let hasRealtime: Bool
    let isCancelled: Bool
    let station: String
    let track: String?
    let trackChanged: Bool
    let mode: String

    private var differs: Bool { hasRealtime && abs(expected.timeIntervalSince(time)) >= 60 }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text(Formatting.time(time))
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .strikethrough(isCancelled || differs, color: isCancelled ? Theme.red : .secondary)
                    .foregroundStyle(differs ? Color.secondary : Color.primary)
                if differs && !isCancelled {
                    Text(Formatting.time(expected))
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(Theme.yellow)
                        .accessibilityLabel(t("Heure estimée %@", Formatting.time(expected)))
                }
            }
            .frame(minWidth: 48, alignment: .leading)

            Text(station)
                .font(.subheadline)
                .lineLimit(2)
            Spacer(minLength: 4)
            if let track {
                Text(Formatting.platformText(track, mode: mode))
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .foregroundStyle(trackChanged ? Color.black : Color.white)
                    .background(trackChanged ? Theme.yellow : Color.white.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }
}

// MARK: - Correspondance

private struct TransferRow: View {
    let station: String
    let walkMinutes: Int?
    let availableMinutes: Int
    let risk: TransferRisk?

    private var color: Color {
        guard let risk else { return .secondary }
        return risk.isMissed ? Theme.redText : Theme.yellow
    }

    private var text: String {
        if let risk {
            return risk.isMissed
                ? t("Correspondance compromise à %@", station)
                : t("Correspondance serrée à %@ : %ld min", station, max(risk.marginMinutes, 0))
        }
        var text = t("Changement à %@ · %ld min", station, max(availableMinutes, 0))
        if let walkMinutes, walkMinutes > 0 { text += " · " + t("%ld min à pied", walkMinutes) }
        return text
    }

    var body: some View {
        Label(text, systemImage: risk == nil ? "figure.walk" : "exclamationmark.triangle.fill")
            .font(.caption.weight(risk == nil ? .regular : .bold))
            .foregroundStyle(color)
            .padding(.leading, 2)
            .padding(.vertical, 2)
    }
}

// MARK: - Détail d'un départ (pastille touchée)

/// Feuille : trajet complet d'un départ, avec un bouton pour le surveiller à la place du train actuel.
struct ConnectionDetailSheet: View {
    let connection: ConnectionInfo
    let isMonitored: Bool
    var onMonitor: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(Formatting.time(connection.plannedDeparture))
                            .font(.system(.largeTitle, design: .rounded).weight(.bold))
                        Text("→ " + Formatting.time(connection.expectedArrival))
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(Formatting.stateText(connection.state))
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(connection.isProblem(threshold: 1) ? Theme.yellow : Theme.green)
                    }
                    if (connection.legs ?? []).isEmpty {
                        Text(t("Détail du trajet indisponible pour ce départ."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        JourneyView(connection: connection)
                    }
                    ForEach(connection.messages ?? []) { message in
                        Label(message.summary, systemImage: "exclamationmark.bubble.fill")
                            .font(.caption)
                            .foregroundStyle(message.affectsService ? Theme.yellow : .secondary)
                    }
                    if isMonitored {
                        Label(t("C'est le train surveillé"), systemImage: "checkmark.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.green)
                    } else if !connection.isCancelled {
                        Button {
                            onMonitor()
                            dismiss()
                        } label: {
                            Label(t("Surveiller ce départ à la place"), systemImage: "bell.badge.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.red)
                        Text(t("L'heure habituelle du trajet passera à %@. Tu peux la changer à tout moment.",
                               Formatting.time(connection.plannedDeparture)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(16)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(t("Détail du départ"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(t("OK")) { dismiss() }
                }
            }
        }
    }
}
