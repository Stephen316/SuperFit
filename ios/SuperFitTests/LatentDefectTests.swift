import Testing
import Foundation
@testable import SuperFit

/// Small defects that were unreachable through the UI but wrong on their own
/// terms — the kind that surface later as a crash report with no repro.
struct LatentDefectTests {

    // MARK: - CyclicalPattern.offset

    /// `day % 0` is a division-by-zero trap. A persisted pattern row with a zero
    /// period is enough to reach it.
    @Test func aZeroPeriodDoesNotTrap() {
        let pattern = CyclicalPattern(periodDays: 0, cyclesObserved: 4,
                                      strength: 0.5, amplitude: 3, profile: [])
        #expect(pattern.offset(forDay: 12) == 0)
    }

    /// A profile shorter than its period is an out-of-bounds read on any day
    /// whose phase lands past the end.
    @Test func aShortProfileDoesNotReadOutOfBounds() {
        let pattern = CyclicalPattern(periodDays: 28, cyclesObserved: 4,
                                      strength: 0.5, amplitude: 3,
                                      profile: [1, 2, 3])
        for day in 0..<40 { #expect(pattern.offset(forDay: day) == 0) }
    }

    /// The valid case still works, including negative day indices.
    @Test func aWellFormedPatternStillOffsets() {
        let profile = (0..<28).map { Double($0) }
        let pattern = CyclicalPattern(periodDays: 28, cyclesObserved: 6,
                                      strength: 0.5, amplitude: 27, profile: profile)
        #expect(pattern.offset(forDay: 0) == 0)
        #expect(pattern.offset(forDay: 5) == 5)       // confidence is 1 at 6 cycles
        #expect(pattern.offset(forDay: 33) == 5)      // wraps
        #expect(pattern.offset(forDay: -23) == 5)     // and wraps negatively
    }

    // MARK: - Exercise.primaryMuscle

    /// Nil, not an ab exercise. It used to answer `.upperAbs` for a lift with no
    /// scores, which nothing downstream could distinguish from a real answer.
    @Test func anExerciseWithNoTensionHasNoPrimaryMuscle() {
        let blank = Exercise(name: "Untagged", category: .barbell, tension: [:])
        #expect(blank.primaryMuscle == nil)
    }

    @Test func thePrimaryMuscleIsTheHighestScored() {
        let bench = Exercise(name: "Bench", category: .barbell,
                             tension: [.chest: 5, .tricepsLateral: 3, .frontDelts: 3])
        #expect(bench.primaryMuscle == .chest)
    }

    // MARK: - Figure aspect ratios

    /// The back constants were generated and then never read, so the back view
    /// was drawn at the front's ratio.
    @Test func frontAndBackUseTheirOwnAspects() {
        #expect(BodyArt.aspect(.male, back: false) == BodyArt.maleFrontAspect)
        #expect(BodyArt.aspect(.male, back: true) == BodyArt.maleBackAspect)
        #expect(BodyArt.aspect(.female, back: false) == BodyArt.femaleFrontAspect)
        #expect(BodyArt.aspect(.female, back: true) == BodyArt.femaleBackAspect)
        // Not the same number, which is the whole reason this matters.
        #expect(BodyArt.maleFrontAspect != BodyArt.maleBackAspect)
    }

    @Test func theRendererAsksPerSide() {
        #expect(BodyDiagram.aspect(.front, .male) == BodyArt.maleFrontAspect)
        #expect(BodyDiagram.aspect(.back, .male) == BodyArt.maleBackAspect)
    }

    // MARK: - avgActiveEnergy window

    /// `asOf` chose where the window began but not where it ended, so an
    /// estimate "as of" a past date still averaged in everything since.
    @Test func activeEnergyRespectsTheUpperBound() {
        let cal = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        // Seven quiet days, then a week of much higher burn after the cut-off.
        var rows: [DailyEnergy] = []
        for d in 1...7 {
            let row = DailyEnergy(date: cal.date(byAdding: .day, value: -d, to: now)!)
            row.activeEnergyKcal = 400
            rows.append(row)
        }
        for d in 1...7 {
            let row = DailyEnergy(date: cal.date(byAdding: .day, value: d, to: now)!)
            row.activeEnergyKcal = 1200
            rows.append(row)
        }
        let average = MetabolicRecordAssembler.avgActiveEnergy(energy: rows, asOf: now)
        #expect(average == 400, "days after asOf must not count, got \(average ?? -1)")
    }
}
