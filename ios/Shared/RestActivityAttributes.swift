import Foundation
#if canImport(ActivityKit)
import ActivityKit

/// The rest countdown shown on the lock screen and in the Dynamic Island.
///
/// Compiled into both the app and the widget extension: the app starts and ends
/// the activity, the extension draws it, and both need the same shape.
///
/// The end date is carried rather than a remaining count so the system can tick
/// the clock itself. A Live Activity cannot be updated once a second — there is
/// a strict budget on updates — so the display must be derivable from a fixed
/// point in time with no further messages from the app.
struct RestActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// When the rest period is up. `Text(timerInterval:)` counts to this.
        var endsAt: Date
    }

    /// Shown above the countdown so a glance says what is resting.
    var exerciseName: String
}
#endif

#if canImport(ActivityKit)
/// A cardio session on the lock screen, counting up rather than down.
///
/// Separate from the rest timer rather than a mode on it: this one pauses, and
/// a paused clock has to be drawn as a frozen number instead of a system-run
/// interval, which is a different view rather than a different value.
struct CardioActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// Where the running clock starts from, already adjusted for any paused
        /// time, so the system can run it without further updates.
        var effectiveStart: Date
        /// Frozen elapsed seconds while paused; nil means the clock is running.
        var pausedElapsed: TimeInterval?
    }

    var activityName: String
}
#endif
