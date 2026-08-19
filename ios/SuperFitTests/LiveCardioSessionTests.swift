import Testing
import Foundation
@testable import SuperFit

/// The live cardio session is the shared source of truth the screen and the
/// lock-screen App Intents both drive, so its clock maths and persistence are
/// what these pin. Dates are injected so nothing depends on wall-clock timing.
@MainActor
struct LiveCardioSessionTests {

    private let base = Date(timeIntervalSince1970: 1_000_000)

    private func makeSession() -> LiveCardioSession {
        let suite = "test.livecardio.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return LiveCardioSession(defaults: defaults)
    }

    @Test func startActivates() {
        let s = makeSession()
        s.start(activityName: "Run", at: base)
        #expect(s.isActive)
        #expect(!s.isPaused)
        #expect(s.activityName == "Run")
    }

    /// Paused time is excluded from elapsed: ran 30 s, paused 20 s, stopped at
    /// wall-clock 60 s → 40 s of actual work.
    @Test func pauseResumeExcludesPausedTime() {
        let s = makeSession()
        s.start(activityName: "Run", at: base)

        s.pause(at: base.addingTimeInterval(30))
        #expect(s.isPaused)
        #expect(abs(s.elapsed - 30) < 0.001)   // frozen while paused

        s.resume(at: base.addingTimeInterval(50))
        #expect(!s.isPaused)
        #expect(abs(s.pausedTotal - 20) < 0.001)

        let final = s.stop(at: base.addingTimeInterval(60))
        #expect(abs(final - 40) < 0.001)
        #expect(!s.isActive)
        #expect(abs(s.lastElapsed - 40) < 0.001)
    }

    @Test func toggleFlipsPauseState() {
        let s = makeSession()
        s.start(activityName: "Run", at: base)
        s.toggle(at: base.addingTimeInterval(10))
        #expect(s.isPaused)
        s.toggle(at: base.addingTimeInterval(25))
        #expect(!s.isPaused)
        #expect(abs(s.pausedTotal - 15) < 0.001)
    }

    /// The Live Activity's running clock counts from a start shifted forward by
    /// paused time, so a system-run timer reads correctly without updates.
    @Test func effectiveStartShiftsByPausedTime() {
        let s = makeSession()
        s.start(activityName: "Run", at: base)
        s.pause(at: base.addingTimeInterval(30))
        s.resume(at: base.addingTimeInterval(50))
        #expect(abs(s.effectiveStart.timeIntervalSince(base) - 20) < 0.001)
    }

    @Test func externalStopRaisesFinishFlagAndClearClears() {
        let s = makeSession()
        s.start(activityName: "Run", at: base)
        s.stop(external: true, at: base.addingTimeInterval(42))
        #expect(s.finishRequestedExternally)
        #expect(abs(s.lastElapsed - 42) < 0.001)

        s.clear()
        #expect(!s.finishRequestedExternally)
        #expect(!s.isActive)
    }

    /// A session must survive the app being relaunched in the background to run
    /// an intent: a fresh instance on the same store restores mid-session.
    @Test func snapshotRestoresIntoAFreshInstance() {
        let suite = "test.livecardio.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = LiveCardioSession(defaults: defaults)
        first.start(activityName: "Ride", at: base)
        first.pause(at: base.addingTimeInterval(15))

        let restored = LiveCardioSession(defaults: defaults)
        #expect(restored.isActive)
        #expect(restored.isPaused)
        #expect(restored.activityName == "Ride")
        #expect(abs(restored.elapsed - 15) < 0.001)
    }
}
