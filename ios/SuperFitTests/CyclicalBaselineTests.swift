import Testing
import Foundation
@testable import SuperFit

/// The detector must be far more willing to do nothing than to do something:
/// levelling a baseline that has no rhythm would corrupt recovery scoring for
/// everyone it touched.
struct CyclicalBaselineTests {

    /// Deterministic pseudo-noise — reproducible across runs, unlike a seeded RNG
    /// whose sequence can change between Swift versions.
    private func noise(_ d: Int, scale: Double = 6) -> Double {
        let a = sin(Double(d) * 12.9898) * 43_758.5453
        return (a - a.rounded(.down) - 0.5) * 2 * scale
    }

    private func series(days: Int, period: Int?, amplitude: Double = 9,
                        drift: Double = 0, noiseScale: Double = 6,
                        skip: (Int) -> Bool = { _ in false }) -> [CyclicalSample] {
        (0..<days).compactMap { d in
            guard !skip(d) else { return nil }
            var v = 55 + drift * Double(d) + noise(d, scale: noiseScale)
            if let period {
                v -= (amplitude / 2) * cos(2 * .pi * Double(d) / Double(period))
            }
            return CyclicalSample(day: d, value: v)
        }
    }

    // MARK: Refuses to fire without evidence

    @Test func rejectsFlatData() {
        #expect(CyclicalBaseline.detect(series(days: 200, period: nil)) == nil)
    }

    @Test func rejectsPureDrift() {
        // Rising fitness lifts HRV steadily — a trend, not a rhythm.
        #expect(CyclicalBaseline.detect(series(days: 200, period: nil, drift: 0.05)) == nil)
    }

    @Test func rejectsTooShortAHistory() {
        // A real rhythm, but only two months of it.
        #expect(CyclicalBaseline.detect(series(days: 60, period: 28)) == nil)
    }

    @Test func rejectsRhythmSmallerThanNoise() {
        #expect(CyclicalBaseline.detect(series(days: 200, period: 28, amplitude: 2)) == nil)
    }

    @Test func rejectsPeriodsOutsidePhysiologicalRange() {
        // A weekly training rhythm must not be mistaken for a monthly one.
        #expect(CyclicalBaseline.detect(series(days: 200, period: 7)) == nil)
    }

    // MARK: Fires on a genuine rhythm

    @Test func detectsAMonthlyRhythmAndItsPeriod() {
        let pattern = CyclicalBaseline.detect(series(days: 240, period: 28))
        let found = try? #require(pattern)
        #expect(found != nil)
        if let found {
            #expect(abs(found.periodDays - 28) <= 1)
            #expect(found.cyclesObserved >= CyclicalBaseline.minCycles)
            #expect(found.amplitude > 4)
        }
    }

    @Test func survivesMissingDaysAndDrift() {
        let pattern = CyclicalBaseline.detect(
            series(days: 240, period: 28, drift: 0.03, skip: { $0 % 5 == 0 }))
        #expect(pattern != nil)
    }

    // MARK: Levelling behaviour

    @Test func levellingReducesCyclicalSpread() {
        let raw = series(days: 240, period: 28)
        let pattern = CyclicalBaseline.detect(raw)
        guard let pattern else {
            Issue.record("expected a pattern to level against")
            return
        }
        let levelled = CyclicalBaseline.levelled(raw, pattern: pattern)

        func spread(_ s: [CyclicalSample]) -> Double {
            let v = s.map(\.value)
            let m = v.reduce(0, +) / Double(v.count)
            return (v.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(v.count - 1)).squareRoot()
        }
        // Removing a real component must tighten the distribution the z-score
        // is measured against.
        #expect(spread(levelled) < spread(raw))
    }

    /// Correction ramps in with evidence rather than switching on at full strength.
    @Test func correctionIsScaledByCyclesObserved() {
        let profile = [Double](repeating: 0, count: 28).enumerated().map { i, _ in
            i < 14 ? 4.0 : -4.0
        }
        func pattern(cycles: Int) -> CyclicalPattern {
            CyclicalPattern(periodDays: 28, cyclesObserved: cycles, strength: 0.2,
                            amplitude: 8, profile: profile)
        }
        #expect(pattern(cycles: 3).confidence == 0.5)
        #expect(pattern(cycles: 6).confidence == 1.0)
        #expect(pattern(cycles: 9).confidence == 1.0)
        #expect(abs(pattern(cycles: 3).offset(forDay: 0) - 2.0) < 0.001)
        #expect(abs(pattern(cycles: 6).offset(forDay: 0) - 4.0) < 0.001)
    }

    @Test func offsetHandlesNegativeAndLargeDayIndices() {
        let profile = (0..<28).map { Double($0) }
        let p = CyclicalPattern(periodDays: 28, cyclesObserved: 6, strength: 0.2,
                                amplitude: 27, profile: profile)
        #expect(p.offset(forDay: 0) == 0)
        #expect(p.offset(forDay: 28) == 0)
        #expect(p.offset(forDay: -28) == 0)
        #expect(p.offset(forDay: -1) == 27)
    }
}
