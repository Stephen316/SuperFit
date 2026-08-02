import Testing
import Foundation
@testable import SuperFit

private let benchID = UUID()
private let squatID = UUID()

private let muscles: [UUID: [MuscleGroup: Int]] = [
    benchID: [.chest: 5, .tricepsLateral: 3, .sideDelts: 2],
    squatID: [.vastusLateralis: 5, .gluteusMaximus: 4, .upperAbs: 2],
]

private func lift(_ daysAgo: Int, _ id: UUID, _ kg: Double, _ reps: Int,
                  warmup: Bool = false) -> LiftRecord {
    LiftRecord(date: Date().addingTimeInterval(-Double(daysAgo) * 86_400),
               exerciseID: id, weightKg: kg, reps: reps, isWarmup: warmup)
}

@Suite struct VolumeAggregatorTests {

    private let week = DateInterval(start: Date().addingTimeInterval(-6 * 86_400),
                                    end: Date().addingTimeInterval(3600))

    @Test func tensionWeightedSetsWarmupsExcluded() {
        let records = [
            lift(1, benchID, 100, 8), lift(1, benchID, 100, 8), lift(1, benchID, 100, 7),
            lift(2, squatID, 60, 5, warmup: true), lift(2, squatID, 80, 5, warmup: true),
            lift(2, squatID, 140, 5), lift(2, squatID, 140, 5), lift(2, squatID, 140, 4),
        ]
        let v = VolumeAggregator().weeklySets(records: records, muscles: muscles, week: week)
        // 3 working bench sets: chest 3×5/5, triceps 3×3/5, shoulders 3×2/5
        #expect(v[.chest] == 3)
        #expect(abs(v[.tricepsLateral]! - 1.8) < 0.001)
        #expect(abs(v[.sideDelts]! - 1.2) < 0.001)
        // 3 working squat sets (warmups ignored): quads 3, glutes 2.4, core 1.2
        #expect(v[.vastusLateralis] == 3)
        #expect(abs(v[.gluteusMaximus]! - 2.4) < 0.001)
        #expect(abs(v[.upperAbs]! - 1.2) < 0.001)
        #expect(v[.lats] == nil)
    }

    @Test func setsOutsideWeekExcluded() {
        let records = [lift(1, benchID, 100, 8), lift(10, benchID, 100, 8)]
        let v = VolumeAggregator().weeklySets(records: records, muscles: muscles, week: week)
        #expect(v[.chest] == 1)
    }

    @Test func tonnageAndFrequency() {
        let records = [
            lift(1, benchID, 100, 8), lift(1, benchID, 100, 8),
            lift(3, squatID, 140, 5),
            lift(3, squatID, 60, 5, warmup: true),
        ]
        let agg = VolumeAggregator()
        #expect(agg.tonnage(records: records, in: week) == 100 * 8 * 2 + 140 * 5)
        #expect(agg.frequency(records: records, in: week) == 2)
    }
}

@Suite struct ProgressionAnalyzerTests {

    private let analyzer = ProgressionAnalyzer()
    private let window = DateInterval(start: Date().addingTimeInterval(-60 * 86_400),
                                      end: Date())

    @Test func epleyE1RM() {
        #expect(abs(analyzer.e1RM(weightKg: 100, reps: 8) - 126.667) < 0.01)
        #expect(analyzer.e1RM(weightKg: 100, reps: 1) == 100)   // single = its own 1RM
        #expect(analyzer.e1RM(weightKg: 0, reps: 5) == 0)
    }

    @Test func highRepSetsCappedAtTwelve() {
        #expect(analyzer.e1RM(weightKg: 60, reps: 20) == analyzer.e1RM(weightKg: 60, reps: 12))
    }

    @Test func fivePercentStrengthGainDetected() {
        let records = [
            lift(50, benchID, 100, 5),   // earlier half best
            lift(45, benchID, 95, 5),
            lift(10, benchID, 105, 5),   // recent half best
            lift(5, benchID, 100, 5),
        ]
        let p = ProgressionAnalyzer().progressions(records: records, window: window)
        #expect(p.count == 1)
        #expect(abs(p[0].change - 0.05) < 0.001)
    }

    @Test func exerciseInOnlyOneHalfOmitted() {
        let records = [lift(5, benchID, 100, 5)]   // recent only
        #expect(ProgressionAnalyzer().progressions(records: records, window: window).isEmpty)
    }

    @Test func warmupsNeverCountTowardProgression() {
        let records = [
            lift(50, benchID, 100, 5),
            lift(5, benchID, 100, 5),
            lift(4, benchID, 180, 1, warmup: true),  // absurd warmup entry
        ]
        let p = ProgressionAnalyzer().progressions(records: records, window: window)
        #expect(abs(p[0].change) < 0.001)            // unchanged, warmup ignored
    }
}

/// The displayed set count is a count, never the weighted total rounded.
struct DisplayedSetCountTests {

    private let agg = VolumeAggregator()
    private let week = DateInterval(start: Date(timeIntervalSince1970: 1_700_000_000),
                                    duration: 7 * 86_400)
    private let lift = UUID()

    private func records(_ n: Int) -> [LiftRecord] {
        (0..<n).map { i in
            LiftRecord(date: week.start.addingTimeInterval(Double(i) * 3600),
                       exerciseID: lift, weightKg: 60, reps: 8, isWarmup: false)
        }
    }

    /// The case that motivated this: two sets that each contribute a fraction
    /// are two sets, not the 1.2 their weighted total rounds to.
    @Test func twoPartialSetsCountAsTwo() {
        let muscles = [lift: [MuscleGroup.chest: 4]]
        let counts = agg.weeklySetCounts(records: records(2), muscles: muscles, week: week)
        let weighted = agg.weeklySets(records: records(2), muscles: muscles, week: week)
        #expect(counts[.chest] == 2)
        #expect(abs((weighted[.chest] ?? 0) - 1.6) < 0.001, "backend stays fractional")
    }

    @Test func tensionBelowFourIsNotACountedSet() {
        let muscles = [lift: [MuscleGroup.chest: 5, MuscleGroup.upperAbs: 3]]
        let counts = agg.weeklySetCounts(records: records(4), muscles: muscles, week: week)
        #expect(counts[.chest] == 4)
        #expect(counts[.upperAbs] == nil,
                "a 3 is real involvement but not why you picked the exercise")
        // It still carries weight in the honest figure.
        let weighted = agg.weeklySets(records: records(4), muscles: muscles, week: week)
        #expect((weighted[.upperAbs] ?? 0) > 0)
    }

    @Test func exactlyFourCountsAndThreeDoesNot() {
        #expect(agg.weeklySetCounts(records: records(1),
                                    muscles: [lift: [MuscleGroup.lats: 4]],
                                    week: week)[.lats] == 1)
        #expect(agg.weeklySetCounts(records: records(1),
                                    muscles: [lift: [MuscleGroup.lats: 3]],
                                    week: week)[.lats] == nil)
    }

    /// Sorting has to use the weighted value or rows that show the same number
    /// would order arbitrarily.
    @Test func weightedValueSeparatesRowsShowingTheSameCount() {
        let muscles = [lift: [MuscleGroup.chest: 5, MuscleGroup.frontDelts: 4]]
        let counts = agg.weeklySetCounts(records: records(3), muscles: muscles, week: week)
        let weighted = agg.weeklySets(records: records(3), muscles: muscles, week: week)
        #expect(counts[.chest] == counts[.frontDelts], "both show 3 sets")
        #expect((weighted[.chest] ?? 0) > (weighted[.frontDelts] ?? 0),
                "but chest sorts above front delts")
    }

    // MARK: - Secondary sets

    /// The squat case, with the catalogue's own numbers: quads at 5, lower back
    /// at 2. Five sets target the quads and assist the lower back, and the table
    /// has to be able to say both.
    @Test func squatTargetsQuadsAndAssistsLowerBack() {
        let muscles = [lift: [MuscleGroup.vastusLateralis: 5, MuscleGroup.erectorSpinae: 2]]
        let counts = agg.weeklySetCounts(records: records(5), muscles: muscles, week: week)
        let secondary = agg.weeklySecondarySetCounts(records: records(5),
                                                     muscles: muscles, week: week)
        #expect(counts[.vastusLateralis] == 5)
        #expect(counts[.erectorSpinae] == nil, "never the target")
        #expect(secondary[.erectorSpinae] == 5, "but worked in all five")
        #expect(secondary[.vastusLateralis] == nil, "targeted sets are not also secondary")
    }

    /// The two counts partition the sets — no set is in both, none is dropped.
    @Test func targetedAndSecondaryDoNotOverlap() {
        let muscles = [lift: [MuscleGroup.lats: 4, MuscleGroup.biceps: 3]]
        let counts = agg.weeklySetCounts(records: records(3), muscles: muscles, week: week)
        let secondary = agg.weeklySecondarySetCounts(records: records(3),
                                                     muscles: muscles, week: week)
        #expect(counts[.lats] == 3)
        #expect(secondary[.lats] == nil)
        #expect(counts[.biceps] == nil)
        #expect(secondary[.biceps] == 3)
    }

    /// A muscle both targeted and assisted in the same week keeps them apart, so
    /// the row shows the targeted count and drops the qualifier.
    @Test func aMuscleCanBeTargetedInOneLiftAndAssistInAnother() {
        let press = UUID()
        let fly = UUID()
        let both = [press, fly].enumerated().map { i, id in
            LiftRecord(date: week.start.addingTimeInterval(Double(i) * 3600),
                       exerciseID: id, weightKg: 40, reps: 10, isWarmup: false)
        }
        let muscles = [press: [MuscleGroup.chest: 5], fly: [MuscleGroup.chest: 2]]
        #expect(agg.weeklySetCounts(records: both, muscles: muscles, week: week)[.chest] == 1)
        #expect(agg.weeklySecondarySetCounts(records: both, muscles: muscles,
                                             week: week)[.chest] == 1)
    }

    /// Warmups and other weeks are excluded from both counts identically.
    @Test func secondaryCountIgnoresWarmupsAndOtherWeeks() {
        let muscles = [lift: [MuscleGroup.erectorSpinae: 2]]
        let warmup = LiftRecord(date: week.start, exerciseID: lift,
                                weightKg: 20, reps: 10, isWarmup: true)
        let lastWeek = LiftRecord(date: week.start.addingTimeInterval(-86_400),
                                  exerciseID: lift, weightKg: 60, reps: 8, isWarmup: false)
        let counted = agg.weeklySecondarySetCounts(records: records(2) + [warmup, lastWeek],
                                                   muscles: muscles, week: week)
        #expect(counted[.erectorSpinae] == 2)
    }
}

/// Band boundaries, pinned because they are a product decision rather than a
/// derived value — a later change to them should be deliberate.
struct MuscleVolumeScaleTests {

    /// Under a full set's worth reads as untrained: that is a muscle carried
    /// through someone else's exercise, not one that was worked.
    @Test func belowTheFloorReadsAsUntrained() {
        for v in [0.0, 0.2, 0.6, 0.8] {
            #expect(MuscleVolumeScale.colour(forWeightedSets: v) == MuscleVolumeScale.untrained,
                    "\(v) weighted sets should not colour as trained")
        }
        // One hard set — tension 4 — is 0.8 weighted and must register.
        #expect(MuscleVolumeScale.colour(forWeightedSets: 0.81) != MuscleVolumeScale.untrained)
    }

    @Test func eachBandHoldsItsRange() {
        let yellow = MuscleVolumeScale.bands[0].colour
        let green = MuscleVolumeScale.bands[1].colour
        let blue = MuscleVolumeScale.bands[2].colour
        for v in [0.81, 1.5, 2.0, 2.99] { #expect(MuscleVolumeScale.colour(forWeightedSets: v) == yellow) }
        for v in [3.0, 4.0, 4.99] { #expect(MuscleVolumeScale.colour(forWeightedSets: v) == green) }
        for v in [5.0, 5.99] { #expect(MuscleVolumeScale.colour(forWeightedSets: v) == blue) }
        for v in [6.0, 12.0, 40.0] {
            #expect(MuscleVolumeScale.colour(forWeightedSets: v) == MuscleVolumeScale.sixPlus)
        }
    }

    /// Boundaries are inclusive at the bottom: 3.0 is "3–4", not the band below.
    @Test func boundariesBelongToTheHigherBand() {
        #expect(MuscleVolumeScale.colour(forWeightedSets: 3.0)
                == MuscleVolumeScale.bands[1].colour)
        #expect(MuscleVolumeScale.colour(forWeightedSets: 5.0)
                == MuscleVolumeScale.bands[2].colour)
    }
}
