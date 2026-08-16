import SwiftUI
import WidgetKit
import ActivityKit

/// Lock-screen and Dynamic Island presentation of the rest countdown.
///
/// Every countdown uses `Text(timerInterval:)`, which the system animates on its
/// own. Nothing here re-renders per second, and the app sends no updates once
/// the activity has started.
struct RestTimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestActivityAttributes.self) { context in
            lockScreen(context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("Rest", systemImage: "timer")
                        .foregroundStyle(.yellow)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    countdown(context.state.endsAt)
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.attributes.exerciseName)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } compactLeading: {
                Image(systemName: "timer").foregroundStyle(.yellow)
            } compactTrailing: {
                countdown(context.state.endsAt)
                    .monospacedDigit()
                    .frame(maxWidth: 44)
            } minimal: {
                Image(systemName: "timer").foregroundStyle(.yellow)
            }
        }
    }

    private func lockScreen(_ context: ActivityViewContext<RestActivityAttributes>) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "timer")
                .font(.system(size: 26))
                .foregroundStyle(.yellow)
            VStack(alignment: .leading, spacing: 2) {
                Text("Rest")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text(context.attributes.exerciseName)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            countdown(context.state.endsAt)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .monospacedDigit()
        }
        .padding(16)
        .activityBackgroundTint(Color.black.opacity(0.55))
    }

    /// A system-driven countdown: the clock keeps ticking with no updates sent.
    private func countdown(_ endsAt: Date) -> some View {
        Text(timerInterval: Date.now...endsAt, countsDown: true)
            .multilineTextAlignment(.trailing)
    }
}
