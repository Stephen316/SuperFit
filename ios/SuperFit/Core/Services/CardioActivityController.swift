import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

/// Puts a running cardio session on the lock screen.
///
/// Updated only when the clock changes character — start, pause, resume — never
/// per second. While running, the widget derives the time from a start date the
/// system animates itself, which is what keeps this inside the update budget.
@MainActor
enum CardioActivityController {
    #if canImport(ActivityKit)
    private static var current: Activity<CardioActivityAttributes>?

    static func start(activityName: String, effectiveStart: Date) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        end()
        current = try? Activity.request(
            attributes: CardioActivityAttributes(activityName: activityName),
            content: .init(state: .init(effectiveStart: effectiveStart,
                                        pausedElapsed: nil), staleDate: nil),
            pushType: nil)
    }

    /// Pausing freezes the number; resuming hands back a start date already
    /// shifted by the time spent paused, so the clock resumes where it stopped.
    static func update(effectiveStart: Date, pausedElapsed: TimeInterval?) {
        guard let activity = current else { return }
        Task {
            await activity.update(.init(state: .init(effectiveStart: effectiveStart,
                                                     pausedElapsed: pausedElapsed),
                                        staleDate: nil))
        }
    }

    static func end() {
        guard let activity = current else { return }
        current = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }
    #else
    static func start(activityName: String, effectiveStart: Date) {}
    static func update(effectiveStart: Date, pausedElapsed: TimeInterval?) {}
    static func end() {}
    #endif
}
