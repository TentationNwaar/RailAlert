import ActivityKit
import WidgetKit
import SwiftUI

/// Affichage du suivi en direct d'un trajet : écran verrouillé et Dynamic Island.
struct TripLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TripActivityAttributes.self) { context in
            LiveLockScreenView(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(Color(red: 0.09, green: 0.12, blue: 0.19))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(AppConfig.tripURL(context.attributes.tripID))
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Formatting.time(state.plannedDeparture))
                            .font(.title2.weight(.bold))
                            .strikethrough(state.isCancelled)
                        if let line = state.line {
                            Text(line).font(.caption.weight(.bold)).foregroundStyle(LiveColors.red)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        LiveStatusText(state: state).font(.headline)
                        if let track = state.track {
                            Text(t("Voie %@", track))
                                .font(.caption.weight(state.trackChanged ? .bold : .regular))
                                .foregroundStyle(state.trackChanged ? LiveColors.yellow : .secondary)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(context.attributes.fromName) → \(context.attributes.toName)")
                            .font(.caption)
                            .lineLimit(1)
                        if let alert = state.alertText {
                            Label(alert, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption2)
                                .foregroundStyle(LiveColors.yellow)
                                .lineLimit(2)
                        }
                        if let alternative = state.alternativeText {
                            Label(t("Alternative : %@", alternative), systemImage: "arrow.triangle.branch")
                                .font(.caption2)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                Image(systemName: LiveColors.symbol(state.severity))
                    .foregroundStyle(LiveColors.color(state.severity))
            } compactTrailing: {
                LiveStatusText(state: state, short: true)
                    .font(.caption.weight(.bold))
            } minimal: {
                Image(systemName: LiveColors.symbol(state.severity))
                    .foregroundStyle(LiveColors.color(state.severity))
            }
            .widgetURL(AppConfig.tripURL(context.attributes.tripID))
        }
    }
}

/// Vue de l'écran verrouillé.
private struct LiveLockScreenView: View {
    let attributes: TripActivityAttributes
    let state: TripActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: LiveColors.symbol(state.severity))
                    .foregroundStyle(LiveColors.color(state.severity))
                Text("\(attributes.fromName) → \(attributes.toName)")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                LiveStatusText(state: state).font(.subheadline.weight(.bold))
            }
            HStack(alignment: .lastTextBaseline, spacing: 10) {
                Text(Formatting.time(state.plannedDeparture))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .strikethrough(state.isCancelled, color: LiveColors.red)
                if !state.isCancelled, (state.delayMinutes ?? 0) > 0 {
                    Text("→ \(Formatting.time(state.expectedDeparture))")
                        .font(.headline)
                        .foregroundStyle(LiveColors.yellow)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    if let line = state.line {
                        Text(line)
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(LiveColors.red, in: RoundedRectangle(cornerRadius: 4))
                    }
                    if let track = state.track {
                        Text(t("Voie %@", track))
                            .font(.caption.weight(state.trackChanged ? .bold : .regular))
                            .foregroundStyle(state.trackChanged ? LiveColors.yellow : .secondary)
                    }
                }
            }
            if let alert = state.alertText {
                Label(alert, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(LiveColors.yellow)
                    .lineLimit(2)
            }
            if let alternative = state.alternativeText {
                Label(t("Alternative : %@", alternative), systemImage: "arrow.triangle.branch")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
        }
        .padding(14)
        .foregroundStyle(.white)
    }
}

/// "À l'heure", "+4 min", "Supprimé".
private struct LiveStatusText: View {
    let state: TripActivityAttributes.ContentState
    var short = false

    var body: some View {
        if state.isCancelled {
            Text(t("Supprimé")).foregroundStyle(LiveColors.red)
        } else if let delay = state.delayMinutes, delay > 0 {
            Text(short ? "+\(delay)'" : t("+%ld min", delay)).foregroundStyle(LiveColors.yellow)
        } else if let delay = state.delayMinutes, delay < 0 {
            Text(short ? "−\(-delay)'" : t("%ld min d'avance", -delay)).foregroundStyle(LiveColors.yellow)
        } else if state.delayMinutes == nil {
            Text(short ? "—" : Formatting.time(state.expectedDeparture))
        } else {
            Text(short ? "OK" : t("À l'heure")).foregroundStyle(LiveColors.green)
        }
    }
}

private enum LiveColors {
    static let red = Color(red: 0.94, green: 0.23, blue: 0.21)
    static let yellow = Color(red: 1.00, green: 0.78, blue: 0.10)
    static let green = Color(red: 0.25, green: 0.80, blue: 0.45)

    static func color(_ severity: Int) -> Color {
        switch severity {
        case 3: return red
        case 2: return yellow
        case 1: return green
        default: return .gray
        }
    }

    static func symbol(_ severity: Int) -> String {
        switch severity {
        case 3: return "xmark.octagon.fill"
        case 2: return "exclamationmark.triangle.fill"
        case 1: return "checkmark.circle.fill"
        default: return "tram.fill"
        }
    }
}
