import SwiftUI
import WidgetKit
import ActivityKit

/// Lock-screen and Dynamic Island presentation of a running cardio session.
struct CardioLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CardioActivityAttributes.self) { context in
            HStack(spacing: 14) {
                Image(systemName: "figure.run")
                    .font(.system(size: 26))
                    .foregroundStyle(.yellow)
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.activityName)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    if context.state.pausedElapsed != nil {
                        Text("Paused").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                clock(context.state)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
            .padding(16)
            .activityBackgroundTint(Color.black.opacity(0.55))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.activityName, systemImage: "figure.run")
                        .foregroundStyle(.yellow)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    clock(context.state)
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
            } compactLeading: {
                Image(systemName: "figure.run").foregroundStyle(.yellow)
            } compactTrailing: {
                clock(context.state).monospacedDigit().frame(maxWidth: 52)
            } minimal: {
                Image(systemName: "figure.run").foregroundStyle(.yellow)
            }
        }
    }

    /// Running: a system-driven interval needing no updates. Paused: a frozen
    /// number, because there is no clock for the system to run.
    @ViewBuilder
    private func clock(_ state: CardioActivityAttributes.ContentState) -> some View {
        if let paused = state.pausedElapsed {
            Text(Duration.seconds(paused).formatted(.time(pattern: .minuteSecond)))
        } else {
            Text(state.effectiveStart, style: .timer)
        }
    }
}
