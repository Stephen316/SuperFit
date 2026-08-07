import Testing
import Foundation
import SwiftUI
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
        // 3 working bench sets. Chest is the prime mover, so 3 whole sets.
        // Triceps (3) and side delts (2) assist and are discounted steeply —
        // under the old score/5 model they scored 1.8 and 1.2, which credited
        // a bench press with more triceps work than it does.
        #expect(v[.chest] == 3)
        // 3 assisting sets at tension 3, saturating towards the top of green.
        #expect(abs(v[.tricepsLateral]! - 1.3502) < 0.001)
        #expect(abs(v[.sideDelts]! - 0.6335) < 0.001)
        // The claim that matters: a bench press is not most of a triceps
        // session. Under the old score/5 model this ratio was 0.6.
        #expect(v[.tricepsLateral]! / v[.chest]! < 0.5)
        // 3 working squat sets, warmups ignored. Glutes score 4, which is direct
        // work rather than assistance, so they earn 0.85 a set.
        #expect(v[.vastusLateralis] == 3)
        #expect(abs(v[.gluteusMaximus]! - 2.55) < 0.001)
        #expect(abs(v[.upperAbs]! - 0.6298) < 0.001)
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

/// The displayed set count is a count, never the effective total rounded.
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
        #expect(abs((weighted[.chest] ?? 0) - 1.7) < 0.001, "backend stays fractional")
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
        // Both are direct work, so both are whole sets to the person doing them —
        // but a 5 outranks a 4, which is what keeps the ordering meaningful.
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

/// The band boundaries and the assisting model. Pinned because they are claims
/// about training, not derived values — changing one should be deliberate.
struct MuscleVolumeScaleTests {

    private let agg = VolumeAggregator()
    private let week = DateInterval(start: Date(timeIntervalSince1970: 1_700_000_000),
                                    duration: 7 * 86_400)
    private let curl = UUID()
    private let row = UUID()

    private func sets(_ n: Int, _ id: UUID) -> [LiftRecord] {
        (0..<n).map { i in
            LiftRecord(date: week.start.addingTimeInterval(Double(i) * 3600),
                       exerciseID: id, weightKg: 30, reps: 10, isWarmup: false)
        }
    }

    private func biceps(curls: Int, rows: Int) -> VolumeAggregator.EffectiveVolume? {
        agg.weeklyVolume(records: sets(curls, curl) + sets(rows, row),
                         muscles: [curl: [.biceps: 5], row: [.lats: 5, .biceps: 3]],
                         week: week)[.biceps]
    }

    private func bicepsColour(curls: Int, rows: Int) -> Color {
        MuscleVolumeScale.colour(for: biceps(curls: curls, rows: rows), muscle: .biceps)
    }

    @Test func nothingLoggedIsUntrained() {
        #expect(MuscleVolumeScale.colour(for: nil, muscle: .biceps) == MuscleVolumeScale.untrained)
        #expect(bicepsColour(curls: 0, rows: 0) == MuscleVolumeScale.untrained)
    }

    /// The complaint that prompted the redesign: a full pull day and no curls
    /// used to paint the biceps purple. Assisting work alone can now reach green
    /// — twenty sets of rows really have worked them harder than most people
    /// work theirs — but never blue, however much of it there is.
    @Test func assistingWorkAloneReachesGreenButNeverBlue() {
        #expect(bicepsColour(curls: 0, rows: 6) == MuscleVolumeScale.insufficient,
                "a few assisting sets is not a trained muscle")
        #expect(bicepsColour(curls: 0, rows: 12) == MuscleVolumeScale.productive,
                "a dozen assisting sets is a real week's work")
        for rows in [20, 40, 80, 200] {
            #expect(bicepsColour(curls: 0, rows: rows) == MuscleVolumeScale.productive,
                    "\(rows) assisting sets should stay green, never blue")
        }
    }

    /// Diminishing returns rather than a cliff: the fifth assisting set is worth
    /// most of its face value, the fiftieth almost nothing.
    @Test func assistingCreditSaturatesSmoothly() {
        let ceiling = MuscleGroup.biceps.weeklyTargets.assistingCeiling
        let e = { (rows: Int) in self.biceps(curls: 0, rows: rows)?.effective ?? 0 }
        #expect(e(200) < ceiling, "never actually reaches the ceiling")
        let firstFive = e(5)
        let secondFive = e(10) - e(5)
        let tenthFive = e(50) - e(45)
        #expect(secondFive < firstFive, "returns diminish")
        #expect(tenthFive < secondFive)
        #expect(tenthFive < 0.2, "and eventually flatten")
    }

    /// Direct work is what moves a muscle through the bands.
    @Test func directSetsDriveTheBands() {
        #expect(bicepsColour(curls: 3, rows: 0) == MuscleVolumeScale.insufficient)
        #expect(bicepsColour(curls: 5, rows: 0) == MuscleVolumeScale.productive)
        #expect(bicepsColour(curls: 8, rows: 0) == MuscleVolumeScale.high)
        #expect(bicepsColour(curls: 11, rows: 0) == MuscleVolumeScale.veryHigh)
    }

    /// Purple starts at the bottom of the reported competitive range for that
    /// muscle size — 16 large, 12 medium, 10 small.
    @Test func purpleBeginsAtCompetitiveVolume() {
        #expect(MuscleGroup.lats.weeklyTargets.veryHighFrom == 16)      // large
        #expect(MuscleGroup.chest.weeklyTargets.veryHighFrom == 12)     // medium
        #expect(MuscleGroup.biceps.weeklyTargets.veryHighFrom == 10)    // small
    }

    /// A big muscle is judged against bigger numbers than a small one, so the
    /// same set count reads differently on quads and biceps.
    @Test func sizeChangesWhatTheSameVolumeMeans() {
        func colour(_ muscle: MuscleGroup, _ effective: Double) -> Color {
            MuscleVolumeScale.colour(for: .init(direct: 1, secondary: 0, effective: effective),
                                     muscle: muscle)
        }
        #expect(colour(.biceps, 8) == MuscleVolumeScale.high)
        #expect(colour(.vastusLateralis, 8) == MuscleVolumeScale.productive)
        #expect(colour(.chest, 8) == MuscleVolumeScale.high)
    }

    /// Boundaries belong to the band above.
    @Test func boundariesBelongToTheHigherBand() {
        let t = MuscleGroup.biceps.weeklyTargets
        func colour(_ effective: Double) -> Color {
            MuscleVolumeScale.colour(for: .init(direct: 1, secondary: 0, effective: effective),
                                     muscle: .biceps)
        }
        #expect(colour(t.productiveFrom) == MuscleVolumeScale.productive)
        #expect(colour(t.productiveFrom - 0.01) == MuscleVolumeScale.insufficient)
        #expect(colour(t.highFrom) == MuscleVolumeScale.high)
        #expect(colour(t.veryHighFrom) == MuscleVolumeScale.veryHigh)
    }

    /// Assistance still counts for something — it tops a muscle up towards the
    /// next band, it just cannot carry one there on its own.
    @Test func assistingWorkStillTopsUpDirectWork() {
        let alone = biceps(curls: 3, rows: 0)?.effective ?? 0
        let topped = biceps(curls: 3, rows: 8)?.effective ?? 0
        #expect(topped > alone)
        #expect(bicepsColour(curls: 3, rows: 8) == MuscleVolumeScale.productive,
                "three curls plus a back day is a productive week for the biceps")
    }

    /// Every muscle is classified, and each class is ordered sensibly.
    @Test func everyMuscleHasCoherentTargets() {
        for muscle in MuscleGroup.allCases {
            let t = muscle.weeklyTargets
            #expect(t.productiveFrom < t.highFrom)
            #expect(t.highFrom < t.veryHighFrom)
            // Assistance asymptotes at the top of green, so it can deliver a
            // productive week and can never deliver a high one.
            #expect(t.assistingCeiling == t.highFrom)
        }
    }

    /// The muscles almost nobody trains directly are judged on a lower bar, so
    /// they report something other than "needs work" every week of your life.
    @Test func tinyMusclesAreReachableByAssistanceAlone() {
        let press = UUID()
        let records = (0..<14).map { i in
            LiftRecord(date: week.start.addingTimeInterval(Double(i) * 3600),
                       exerciseID: press, weightKg: 60, reps: 8, isWarmup: false)
        }
        let v = agg.weeklyVolume(records: records,
                                 muscles: [press: [.chest: 5, .serratus: 2]],
                                 week: week)
        #expect(MuscleGroup.serratus.size == .tiny)
        #expect(MuscleVolumeScale.colour(for: v[.serratus], muscle: .serratus)
                == MuscleVolumeScale.productive,
                "fourteen sets of pressing is a worked serratus")
    }
}

/// The whole-body summary shown under the diagram.
struct OverallBandTests {

    private let agg = VolumeAggregator()
    private let week = DateInterval(start: Date(timeIntervalSince1970: 1_700_000_000),
                                    duration: 7 * 86_400)

    private func volumes(_ tension: [MuscleGroup: Int], sets n: Int)
        -> [MuscleGroup: VolumeAggregator.EffectiveVolume] {
        let id = UUID()
        let records = (0..<n).map { i in
            LiftRecord(date: week.start.addingTimeInterval(Double(i) * 3600),
                       exerciseID: id, weightKg: 40, reps: 10, isWarmup: false)
        }
        return agg.weeklyVolume(records: records, muscles: [id: tension], week: week)
    }

    @Test func anEmptyWeekIsNotTrained() {
        #expect(MuscleVolumeScale.overall([:]) == .untrained)
    }

    /// Muscles you never touched still count. Training one muscle hard does not
    /// make the body's week a good one.
    @Test func oneHardMuscleDoesNotCarryTheWholeBody() {
        let v = volumes([.biceps: 5], sets: 20)
        #expect(MuscleVolumeScale.band(for: v[.biceps], muscle: .biceps) == .veryHigh)
        #expect(MuscleVolumeScale.overall(v) == .untrained,
                "one muscle out of 37 cannot lift the average off the floor")
    }

    /// Everything on track reads as on track.
    @Test func aBalancedWeekReadsOnTrack() {
        var v: [MuscleGroup: VolumeAggregator.EffectiveVolume] = [:]
        for muscle in MuscleGroup.allCases {
            let target = muscle.weeklyTargets
            let mid = (target.productiveFrom + target.highFrom) / 2
            v[muscle] = .init(direct: Int(mid), secondary: 0, effective: mid)
        }
        #expect(MuscleVolumeScale.overall(v) == .onTrack)
    }

    /// And the summary tracks the bands rather than the raw numbers, so a body
    /// of large muscles at 8 sets is judged differently from small ones at 8.
    @Test func theSummaryUsesEachMusclesOwnTargets() {
        var v: [MuscleGroup: VolumeAggregator.EffectiveVolume] = [:]
        for muscle in MuscleGroup.allCases {
            v[muscle] = .init(direct: 8, secondary: 0, effective: 8)
        }
        // 8 sets is "on track" for a large muscle and "high" for a small one,
        // so the body average lands between the two.
        #expect(MuscleVolumeScale.band(for: v[.lats], muscle: .lats) == .onTrack)
        #expect(MuscleVolumeScale.band(for: v[.biceps], muscle: .biceps) == .high)
        #expect(MuscleVolumeScale.overall(v) >= .onTrack)
    }
}
