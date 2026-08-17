import SwiftUI
import WidgetKit
import ActivityKit
import AppIntents

/// Lock-screen and Dynamic Island presentation of a running cardio session,
/// with interactive Pause/Resume and End controls.
struct CardioLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CardioActivityAttributes.self) { context in
            VStack(spacing: 12) {
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
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    logoBadge
                }
                controls(context.state)
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
                DynamicIslandExpandedRegion(.bottom) {
                    controls(context.state)
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

    /// The SuperFit mark, top-right — a circular crop of the app logo. Lives in
    /// the widget's own asset catalog because the extension can't reach the
    /// app target's assets.
    private var logoBadge: some View {
        Image("SuperFitLogo")
            .resizable()
            .scaledToFill()
            .frame(width: 26, height: 26)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.18), lineWidth: 0.5))
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

    /// Pause/Resume toggle plus End, backed by the Live Activity App Intents.
    /// One toggle button: its icon and title follow the paused state, so pause
    /// and resume share a control the way Apple's own workout activity does.
    @ViewBuilder
    private func controls(_ state: CardioActivityAttributes.ContentState) -> some View {
        let paused = state.pausedElapsed != nil
        HStack(spacing: 10) {
            Button(intent: ToggleCardioPauseIntent()) {
                Label(paused ? "Resume" : "Pause",
                      systemImage: paused ? "play.fill" : "pause.fill")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity)
            }
            .tint(.yellow)

            Button(intent: StopCardioIntent()) {
                Label("End", systemImage: "stop.fill")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity)
            }
            .tint(.red)
        }
        .buttonStyle(.borderedProminent)
        .labelStyle(.titleAndIcon)
    }
}
