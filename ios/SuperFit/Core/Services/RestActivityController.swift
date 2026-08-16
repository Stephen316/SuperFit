import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

/// Puts the rest countdown on the lock screen and in the Dynamic Island.
///
/// Deliberately fire-and-forget: the activity carries an end date, so the system
/// runs the clock and no updates are sent while it counts. Live Activities have
/// a hard budget on updates, and a per-second push would exhaust it long before
/// a set is over.
@MainActor
enum RestActivityController {
    #if canImport(ActivityKit)
    private static var current: Activity<RestActivityAttributes>?

    /// True when the device and the user's settings both allow one.
    static var isAvailable: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    static func start(exercise: String, endsAt: Date) {
        guard isAvailable else { return }
        // One at a time: a second rest replaces the first rather than stacking
        // two countdowns on the lock screen.
        end()
        current = try? Activity.request(
            attributes: RestActivityAttributes(exerciseName: exercise),
            content: .init(state: .init(endsAt: endsAt), staleDate: endsAt),
            pushType: nil)
    }

    static func end() {
        guard let activity = current else { return }
        current = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }
    #else
    static var isAvailable: Bool { false }
    static func start(exercise: String, endsAt: Date) {}
    static func end() {}
    #endif
}
