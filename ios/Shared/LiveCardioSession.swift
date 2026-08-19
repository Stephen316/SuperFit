import Foundation
import Observation

/// The single source of truth for a live cardio session's clock and pause state.
///
/// Lifted out of `LiveCardioView` so a lock-screen App Intent — which runs
/// outside any view — can pause, resume or stop the very session the screen is
/// showing. Deliberately free of ActivityKit and SwiftData so it compiles into
/// the widget extension too: the app reflects its changes onto the Live Activity
/// through `onChange`, and a snapshot is persisted so a session survives the app
/// being suspended or relaunched in the background to run an intent.
///
/// Dates are injectable on every command so the state machine is testable
/// without sleeping; the live UI passes the default `.now`.
@MainActor
@Observable
final class LiveCardioSession {
    static let shared = LiveCardioSession()

    private(set) var activityName = ""
    private(set) var isActive = false
    private(set) var isPaused = false
    private(set) var startedAt = Date.now
    /// Seconds spent paused, so they can be subtracted from wall-clock elapsed.
    private(set) var pausedTotal: TimeInterval = 0
    private(set) var pauseStartedAt: Date?
    /// Elapsed seconds captured the moment the session stopped, so the view can
    /// save the workout with exactly the duration the user saw — even when the
    /// stop arrived from the lock screen.
    private(set) var lastElapsed: TimeInterval = 0
    /// Raised when a stop came from outside the view (the Live Activity's End
    /// button). The view lowers it once it has saved the finished workout.
    var finishRequestedExternally = false

    /// App-only bridge onto ActivityKit. nil in the widget process and until the
    /// app registers it; never part of the observable state, so reflecting a
    /// change never itself invalidates a view.
    @ObservationIgnored var onChange: ((LiveCardioSession) -> Void)?

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        restore()
    }

    // MARK: - Derived

    /// Running seconds, excluding paused time. Frozen while paused; the captured
    /// final value once stopped.
    var elapsed: TimeInterval {
        guard isActive else { return lastElapsed }
        let reference = isPaused ? (pauseStartedAt ?? Date.now) : Date.now
        return max(reference.timeIntervalSince(startedAt) - pausedTotal, 0)
    }

    /// Start date shifted forward by paused time, so a system-run timer on the
    /// Live Activity reads correctly without per-second updates.
    var effectiveStart: Date { startedAt.addingTimeInterval(pausedTotal) }

    // MARK: - Commands

    func start(activityName: String, at date: Date = .now) {
        self.activityName = activityName
        startedAt = date
        pausedTotal = 0
        pauseStartedAt = nil
        lastElapsed = 0
        isPaused = false
        isActive = true
        finishRequestedExternally = false
        commit()
    }

    func pause(at date: Date = .now) {
        guard isActive, !isPaused else { return }
        pauseStartedAt = date
        isPaused = true
        commit()
    }

    func resume(at date: Date = .now) {
        guard isActive, isPaused else { return }
        if let started = pauseStartedAt {
            pausedTotal += max(date.timeIntervalSince(started), 0)
        }
        pauseStartedAt = nil
        isPaused = false
        commit()
    }

    func toggle(at date: Date = .now) { isPaused ? resume(at: date) : pause(at: date) }

    /// Ends the session and returns the final elapsed seconds. `external` marks a
    /// stop from the Live Activity, so the view knows to run its save flow.
    @discardableResult
    func stop(external: Bool = false, at date: Date = .now) -> TimeInterval {
        guard isActive else { return lastElapsed }
        if isPaused, let started = pauseStartedAt {
            pausedTotal += max(date.timeIntervalSince(started), 0)
            pauseStartedAt = nil
        }
        lastElapsed = max(date.timeIntervalSince(startedAt) - pausedTotal, 0)
        isActive = false
        isPaused = false
        if external { finishRequestedExternally = true }
        commit()
        return lastElapsed
    }

    /// Clears a session the view has finished handling (saved or discarded). The
    /// Live Activity is already ended by `stop`, so this doesn't re-notify.
    func clear() {
        isActive = false
        isPaused = false
        finishRequestedExternally = false
        persist()
    }

    // MARK: - Reflection + persistence

    private func commit() {
        persist()
        onChange?(self)
    }

    private struct Snapshot: Codable {
        var activityName: String
        var isActive: Bool
        var isPaused: Bool
        var startedAt: Date
        var pausedTotal: TimeInterval
        var pauseStartedAt: Date?
        var lastElapsed: TimeInterval
    }

    private static let storageKey = "liveCardioSession.v1"

    private func persist() {
        let snap = Snapshot(activityName: activityName, isActive: isActive,
                            isPaused: isPaused, startedAt: startedAt,
                            pausedTotal: pausedTotal, pauseStartedAt: pauseStartedAt,
                            lastElapsed: lastElapsed)
        if let data = try? JSONEncoder().encode(snap) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }

    private func restore() {
        guard let data = defaults.data(forKey: Self.storageKey),
              let snap = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        activityName = snap.activityName
        isActive = snap.isActive
        isPaused = snap.isPaused
        startedAt = snap.startedAt
        pausedTotal = snap.pausedTotal
        pauseStartedAt = snap.pauseStartedAt
        lastElapsed = snap.lastElapsed
    }
}
