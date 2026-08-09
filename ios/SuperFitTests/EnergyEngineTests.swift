import Testing
import Foundation
@testable import SuperFit

/// Energy is an openly heuristic battery, but its behaviour is still pinned: it
/// starts from the morning charge, drains with the clock and exertion, works from
/// phone-only signals when no watch is present, and reports nothing when there is
/// genuinely nothing to read.
struct EnergyEngineTests {
    private func inputs(recovery: Double? = nil, strain: Double? = nil,
                        active: Double? = nil, steps: Int? = nil,
                        intake: Double? = nil, target: Double? = nil,
                        frac: Double) -> EnergyEngine.Inputs {
        .init(recoveryScore: recovery, strain: strain, activeEnergyKcal: active,
              steps: steps, intakeKcal: intake, targetKcal: target, dayFraction: frac)
    }

    @Test("A rested morning reads near the recovery charge")
    func morningCharge() {
        let r = EnergyEngine().evaluate(inputs(recovery: 90, frac: 0))
        #expect(r?.level == 90)
        #expect(r?.band == .charged)
    }

    @Test("The day and a hard session draw it down")
    func drainsThroughDay() {
        // 90 − 22 (full day) − 35·0.8 (strain 80) = 90 − 22 − 28 = 40
        let r = EnergyEngine().evaluate(inputs(recovery: 90, strain: 80, frac: 1))
        #expect(r?.level == 40)
        #expect(r?.band == .steady)
        #expect(r?.dataCompleteness == 2.0 / 3.0)
    }

    @Test("It works from phone steps alone, with no watch")
    func phoneOnly() {
        // base 72 − 22·0.5 − 20·(8000/12000) = 72 − 11 − 13.33 = 47.67 → 48
        let r = EnergyEngine().evaluate(inputs(steps: 8000, frac: 0.5))
        #expect(r?.level == 48)
        #expect(r?.band == .steady)
        #expect(r?.dataCompleteness == 1.0 / 3.0)
    }

    @Test("With no signal at all, there is no reading")
    func noData() {
        #expect(EnergyEngine().evaluate(inputs(frac: 0.5)) == nil)
    }

    @Test("Under-fuelling for the time of day drains a little")
    func underFuelled() {
        // 80 − 22·0.5 − fuel; ratio = 200/(2000·0.5)=0.2 → (0.2−1)·12 = −9.6
        let r = EnergyEngine().evaluate(inputs(recovery: 80, intake: 200, target: 2000, frac: 0.5))
        #expect(r?.level == round(80 - 11 - 9.6)) // 59
        // On-pace fuelling neither rewards nor punishes.
        let onPace = EnergyEngine().evaluate(inputs(recovery: 80, intake: 1000, target: 2000, frac: 0.5))
        #expect(onPace?.level == 69)
    }

    @Test("An empty morning diary is unknown, not under-fuelled")
    func noFuelPenaltyEarly() {
        // frac 0.2 (< 0.3 guard) → fuelling not judged, so no drain and no signal.
        let r = EnergyEngine().evaluate(inputs(recovery: 80, intake: 0, target: 2000, frac: 0.2))
        #expect(r?.level == round(80 - 22 * 0.2)) // 76
        #expect(r?.dataCompleteness == 1.0 / 3.0) // only recovery counted
    }

    @Test("It clamps to 0 and bands as Drained")
    func clampsLow() {
        let r = EnergyEngine().evaluate(inputs(recovery: 10, strain: 100, frac: 1))
        #expect(r?.level == 0)
        #expect(r?.band == .drained)
    }

    @Test("Band boundaries hold on the rounded level")
    func bands() {
        // 70 → charged, 69 → steady, 40 → steady, 39 → low, 20 → low, 19 → drained
        #expect(EnergyEngine().evaluate(inputs(recovery: 70, frac: 0))?.band == .charged)
        #expect(EnergyEngine().evaluate(inputs(recovery: 69, frac: 0))?.band == .steady)
        #expect(EnergyEngine().evaluate(inputs(recovery: 40, frac: 0))?.band == .steady)
        #expect(EnergyEngine().evaluate(inputs(recovery: 39, frac: 0))?.band == .low)
        #expect(EnergyEngine().evaluate(inputs(recovery: 20, frac: 0))?.band == .low)
        #expect(EnergyEngine().evaluate(inputs(recovery: 19, frac: 0))?.band == .drained)
    }
}
