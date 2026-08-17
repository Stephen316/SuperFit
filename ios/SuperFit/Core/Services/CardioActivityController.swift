import Foundation
#if canImport(ActivityKit)
// ActivityKit's `Activity` isn't Sendable-audited, so calling its async
// update/end from the main actor otherwise warns "sending non-Sendable"; the
// calls are genuinely fire-and-forget and safe.
@preconcurrency import ActivityKit
#endif

/// Reflects a `LiveCardioSession` onto the lock screen.
///
/// The app's only ActivityKit call site: `LiveCardioSession` (in the Shared
/// target) stays free of ActivityKit so it compiles into the widget, and the app
/// registers `apply` as the session's `onChange` bridge. The controller then
/// starts, updates or ends the Live Activity to match the session — updated only
/// when the clock changes character (start, pause, resume, stop), never per
/// second: while running, the widget derives time from a start date the system
/// animates itself, which is what keeps this inside the update budget.
@MainActor
enum CardioActivityController {
    #if canImport(ActivityKit)
    private static var current: Activity<CardioActivityAttributes>?

    /// Brings the Live Activity into line with the session's current state.
    static func apply(_ session: LiveCardioSession) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        guard session.isActive else { end(); return }

        let state = CardioActivityAttributes.ContentState(
            effectiveStart: session.effectiveStart,
            pausedElapsed: session.isPaused ? session.elapsed : nil)

        if let activity = current {
            Task { await activity.update(.init(state: state, staleDate: nil)) }
        } else {
            current = try? Activity.request(
                attributes: CardioActivityAttributes(activityName: session.activityName),
                content: .init(state: state, staleDate: nil),
                pushType: nil)
        }
    }

    static func end() {
        guard let activity = current else { return }
        current = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }
    #else
    static func apply(_ session: LiveCardioSession) {}
    static func end() {}
    #endif
}
