import Testing
import Foundation
@testable import SuperFit

/// The HR-based rest decision (#26). Pure maths, so it's pinned here off-watch.
struct HRRestAdvisorTests {

    private let advisor = HRRestAdvisor()

    @Test func targetIsHalfwayBackToBaseline() {
        // Peak 160, baseline 60, recover 50% → target 110.
        #expect(advisor.targetHR(peakHR: 160, baselineHR: 60) == 110)
    }

    @Test func targetFallsBackToAFixedDropWithoutBaseline() {
        // No baseline → peak minus 25 bpm.
        #expect(advisor.targetHR(peakHR: 150, baselineHR: nil) == 125)
    }

    @Test func staysRestingBelowTheFloorEvenIfRecovered() {
        // HR already at target, but only 10 s in — the floor keeps it resting.
        let r = advisor.readiness(currentHR: 100, peakHR: 160, baselineHR: 60, elapsed: 10)
        #expect(r == .resting)
    }

    @Test func readyOncePastFloorAndAtTarget() {
        let r = advisor.readiness(currentHR: 108, peakHR: 160, baselineHR: 60, elapsed: 45)
        #expect(r == .ready)
    }

    @Test func stillRestingWhenHRTooHigh() {
        let r = advisor.readiness(currentHR: 140, peakHR: 160, baselineHR: 60, elapsed: 60)
        #expect(r == .resting)
    }

    @Test func readyAtTheCapEvenIfHRNeverDrops() {
        // Unreachable target must not trap the user resting past the cap.
        let r = advisor.readiness(currentHR: 155, peakHR: 160, baselineHR: 60, elapsed: 240)
        #expect(r == .ready)
    }

    @Test func missingHRKeepsResting() {
        let r = advisor.readiness(currentHR: nil, peakHR: 160, baselineHR: 60, elapsed: 60)
        #expect(r == .resting)
    }

    // MARK: Resume-HR learning

    private func freshStore() -> ResumeHRStore {
        let suite = "test.resumeHR.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return ResumeHRStore(defaults: defaults)
    }

    @Test func learnedResumeHRNeedsEnoughSamples() {
        let store = freshStore()
        store.record(90); store.record(95); store.record(100)
        #expect(store.learnedResumeHR() == nil)      // < 5 samples
        store.record(98); store.record(92)
        #expect(store.learnedResumeHR() == 95)       // median of 5
    }

    @Test func zeroOrNegativeResumeHRIsIgnored() {
        let store = freshStore()
        store.record(0); store.record(-5)
        #expect(store.samples.isEmpty)
    }
}
