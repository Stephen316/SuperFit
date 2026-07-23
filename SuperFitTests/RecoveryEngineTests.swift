import Testing
import Foundation
@testable import SuperFit

@Suite struct RecoveryEngineTests {

    @Test func fullRecoveryScoresHigh() {
        var i = RecoveryInputs()
        i.asleepMinutes = 490; i.sleepEfficiency = 0.95
        i.hrv = 90; i.hrvBaselineMean = 70; i.hrvBaselineSD = 12
        i.restingHR = 50; i.rhrBaselineMean = 55; i.rhrBaselineSD = 4
        i.acuteLoad = 100; i.chronicLoad = 100
        let r = RecoveryEngine().evaluate(i)
        #expect(r.score >= 80)
        #expect(r.recommendation == .normalTraining || r.recommendation == .pushIntensity)
        #expect(r.dataCompleteness == 1)
    }

    @Test func poorSleepAndSuppressedHRVScoresLow() {
        var i = RecoveryInputs()
        i.asleepMinutes = 300; i.sleepEfficiency = 0.7
        i.hrv = 45; i.hrvBaselineMean = 70; i.hrvBaselineSD = 12
        i.restingHR = 64; i.rhrBaselineMean = 55; i.rhrBaselineSD = 4
        i.acuteLoad = 180; i.chronicLoad = 100
        let r = RecoveryEngine().evaluate(i)
        #expect(r.score < 55)
        #expect(r.recommendation == .reduceVolume || r.recommendation == .recoveryFocus)
    }

    @Test func missingComponentsRenormalizeAndFlagCompleteness() {
        var i = RecoveryInputs()
        i.asleepMinutes = 480; i.sleepEfficiency = 0.9
        // no HRV / RHR / load
        let r = RecoveryEngine().evaluate(i)
        #expect(r.dataCompleteness == 0.25)
        #expect(r.hrvScore == nil)
        #expect(r.score > 0)
    }

    @Test func highACWRPenalizesLoad() {
        var i = RecoveryInputs()
        i.acuteLoad = 200; i.chronicLoad = 100     // ACWR 2.0
        let r = RecoveryEngine().evaluate(i)
        #expect((r.loadScore ?? 100) < 60)
    }
}
