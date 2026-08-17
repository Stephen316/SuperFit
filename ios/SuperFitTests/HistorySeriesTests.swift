import Testing
import Foundation
@testable import SuperFit

private let cal = Calendar(identifier: .gregorian)
private let today = cal.startOfDay(for: Date(timeIntervalSince1970: 1_750_000_000))
private func day(_ offset: Int) -> Date { cal.date(byAdding: .day, value: offset, to: today)! }

struct HistorySeriesTests {

    private var prior: MetabolismEngine.Prior {
        .init(sex: .male, ageYears: 30, heightCm: 180, activity: .moderate)
    }

    /// 60 days of steady logging losing 0.5 kg/week.
    private func steadyRecords() -> [DailyRecord] {
        (0..<60).map { i in
            DailyRecord(date: day(-59 + i), intakeKcal: 2500,
                        weightKg: 85 - Double(i) * (0.5 / 7))
        }
    }

    // MARK: TDEE backfill

    /// The point of recomputing rather than reading stored rows: history exists
    /// for every day with data, not only days the app happened to be opened.
    @Test func tdeeIsBackfilledForEveryDayNotJustLoggedOnes() {
        let bands = HistorySeries.tdee(records: steadyRecords(), prior: prior,
                                       from: day(-30), to: day(0), calendar: cal)
        #expect(bands.count == 31)
        #expect(Set(bands.map { cal.startOfDay(for: $0.date) }).count == 31)
    }

    @Test func tdeeMatchesTheEngineForTheSameDay() {
        let records = steadyRecords()
        let bands = HistorySeries.tdee(records: records, prior: prior,
                                       from: day(-5), to: day(0), calendar: cal)
        let direct = MetabolismEngine().estimate(records: records, windowDays: 30,
                                                 prior: prior, asOf: day(0))
        #expect(bands.last?.value == direct.tdeeKcal)
    }

    /// The moving-window implementation must be numerically identical to the
    /// original independent engine call for every requested day, including
    /// sparse intake and multiple records on a day.
    @Test func movingWindowMatchesIndependentEngineCallsExactly() {
        var records: [DailyRecord] = []
        for i in 0..<365 {
            let date = day(-364 + i).addingTimeInterval(Double(i % 4) * 1_800)
            let intake: Double? = i.isMultiple(of: 5)
                ? nil : 2_100 + Double(i % 11) * 37
            let weight: Double? = i.isMultiple(of: 3)
                ? nil : 88 - Double(i) * 0.015
            records.append(DailyRecord(date: date, intakeKcal: intake,
                                       weightKg: weight))
        }
        records.append(DailyRecord(date: day(-20).addingTimeInterval(7_200),
                                   intakeKcal: nil, weightKg: 84.2))
        let requested = stride(from: -330, through: 0, by: 3).map(day)
        let optimized = HistorySeries.metabolismEstimates(
            records: records, windowDays: 30, on: requested, calendar: cal) { _ in prior }
        let engine = MetabolismEngine()

        #expect(optimized.count == requested.count)
        for (date, estimate) in optimized {
            let direct = engine.estimate(records: records, windowDays: 30,
                                         prior: prior, asOf: date)
            #expect(estimate.tdeeKcal == direct.tdeeKcal)
            #expect(estimate.confidence == direct.confidence)
            #expect(estimate.trendSlopeKgPerWeek == direct.trendSlopeKgPerWeek)
            #expect(estimate.avgIntakeKcal == direct.avgIntakeKcal)
            #expect(estimate.smoothedWeightKg == direct.smoothedWeightKg)
            #expect(estimate.standardErrorKcal == direct.standardErrorKcal)
        }
    }

    /// Steady intake with steady loss should recover ~2500 + 550 = 3050.
    @Test func tdeeRecoversTheTrueValueOnCleanData() {
        let bands = HistorySeries.tdee(records: steadyRecords(), prior: prior,
                                       from: day(-2), to: day(0), calendar: cal)
        let value = try? #require(bands.last?.value)
        if let value { #expect(abs(value - 3050) < 120) }
    }

    /// The band has to narrow as the estimate earns confidence, or it says
    /// nothing useful.
    @Test func uncertaintyBandNarrowsAsConfidenceGrows() {
        let records = steadyRecords()
        let early = HistorySeries.tdee(records: records, prior: prior,
                                       from: day(-52), to: day(-52), calendar: cal).first
        let late = HistorySeries.tdee(records: records, prior: prior,
                                      from: day(0), to: day(0), calendar: cal).first
        guard let early, let late else {
            Issue.record("expected estimates at both ends")
            return
        }
        let earlyWidth = (early.upper - early.lower) / early.value
        let lateWidth = (late.upper - late.lower) / late.value
        #expect(lateWidth < earlyWidth)
    }

    @Test func noBandsBeforeAnythingIsLogged() {
        let weightOnly = (0..<20).map {
            DailyRecord(date: day(-19 + $0), intakeKcal: nil, weightKg: 82)
        }
        let bands = HistorySeries.tdee(records: weightOnly, prior: prior,
                                       from: day(-19), to: day(0), calendar: cal)
        #expect(bands.isEmpty)
    }

    // MARK: Shaping

    @Test func dailyKeepsTheLastReadingPerDay() {
        struct Row { let date: Date; let value: Double? }
        let rows = [
            Row(date: day(0).addingTimeInterval(3600), value: 50),
            Row(date: day(0).addingTimeInterval(7200), value: 60),   // later, wins
            Row(date: day(-1), value: 40),
            Row(date: day(-2), value: nil),                          // dropped
        ]
        let points = HistorySeries.daily(rows, date: \.date, value: \.value, calendar: cal)
        #expect(points.count == 2)
        #expect(points.last?.value == 60)
        #expect(points.first?.value == 40)
    }

    @Test func dailyReturnsPointsInChronologicalOrder() {
        struct Row { let date: Date; let value: Double? }
        let rows = (0..<10).map { Row(date: day(-$0), value: Double($0)) }
        let points = HistorySeries.daily(rows, date: \.date, value: \.value, calendar: cal)
        #expect(points == points.sorted { $0.date < $1.date })
    }

    /// A partial average drawn as a line reads as a trend that isn't there.
    @Test func rollingMeanWithholdsUntilAFullWindowExists() {
        let short = (0..<5).map { HistoryPoint(date: day(-$0), value: 100) }
        #expect(HistorySeries.rollingMean(short, window: 7).isEmpty)

        let long = (0..<10).map { HistoryPoint(date: day(-9 + $0), value: 100) }
        let mean = HistorySeries.rollingMean(long, window: 7)
        #expect(mean.count == 4)
        #expect(mean.allSatisfy { abs($0.value - 100) < 0.001 })
    }

    @Test func rollingMeanSmoothsASpike() {
        var values = [Double](repeating: 100, count: 14)
        values[13] = 800
        let points = values.enumerated().map {
            HistoryPoint(date: day(-13 + $0.offset), value: $0.element)
        }
        let mean = HistorySeries.rollingMean(points, window: 7)
        // The spike lifts the mean but nowhere near its own size.
        #expect(mean.last!.value > 100)
        #expect(mean.last!.value < 250)
    }

    // MARK: Change

    /// Endpoint-to-endpoint would let one noisy weigh-in define the period.
    @Test func changeUsesEdgeAveragesNotSinglePoints() throws {
        var values = [Double](repeating: 80, count: 20)
        values[0] = 95          // one bad reading at the start
        let points = values.enumerated().map {
            HistoryPoint(date: day(-19 + $0.offset), value: $0.element)
        }
        let change = try #require(HistorySeries.change(points, edgeDays: 7))
        // A raw first-to-last read would say −15; averaging the edges says ~−2.
        #expect(abs(change) < 3)
    }

    @Test func changeIsNilWithoutEnoughPoints() {
        #expect(HistorySeries.change([]) == nil)
        #expect(HistorySeries.change([HistoryPoint(date: day(0), value: 80)]) == nil)
    }

    @Test func changeIsSignedInTheDirectionOfTravel() {
        let rising = (0..<20).map { HistoryPoint(date: day(-19 + $0), value: Double(80 + $0)) }
        #expect(HistorySeries.change(rising)! > 0)
        let falling = (0..<20).map { HistoryPoint(date: day(-19 + $0), value: Double(100 - $0)) }
        #expect(HistorySeries.change(falling)! < 0)
    }

    // MARK: Training

    @Test func weeklySetsBucketsByIsoWeek() {
        let id = UUID()
        let records = (0..<14).map {
            LiftRecord(date: day(-13 + $0), exerciseID: id, weightKg: 100, reps: 8,
                       isWarmup: false)
        }
        let points = HistorySeries.weeklySets(records: records,
                                              muscles: [id: [.chest: 5]],
                                              muscle: .chest,
                                              from: day(-13), to: day(0))
        #expect(points.count >= 2)
        // 14 daily sets at full tension spread across the weeks.
        #expect(abs(points.reduce(0) { $0 + $1.value } - 14) < 0.001)
    }

    @Test func e1RMHistoryKeepsTheBestSetOfEachWeek() {
        let id = UUID()
        let records = [
            LiftRecord(date: day(-2), exerciseID: id, weightKg: 100, reps: 5, isWarmup: false),
            LiftRecord(date: day(-1), exerciseID: id, weightKg: 110, reps: 5, isWarmup: false),
            LiftRecord(date: day(-1), exerciseID: id, weightKg: 60, reps: 5, isWarmup: true),
        ]
        let points = HistorySeries.e1RMHistory(records: records, exerciseID: id,
                                               from: day(-7), to: day(0))
        let best = ProgressionAnalyzer().e1RM(weightKg: 110, reps: 5)
        #expect(points.count == 1)
        #expect(abs(points[0].value - best) < 0.001)
    }

    @Test func e1RMHistoryIgnoresOtherExercises() {
        let mine = UUID(), theirs = UUID()
        let records = [
            LiftRecord(date: day(-1), exerciseID: theirs, weightKg: 200, reps: 5, isWarmup: false),
        ]
        #expect(HistorySeries.e1RMHistory(records: records, exerciseID: mine,
                                          from: day(-7), to: day(0)).isEmpty)
    }

    // MARK: Energy balance

    @Test func energyBalanceIsIntakeMinusExpenditure() {
        let intake = [HistoryPoint(date: day(-1), value: 2500),
                      HistoryPoint(date: day(0), value: 3200)]
        let tdee = [HistoryBand(date: day(-1), value: 3050, lower: 2900, upper: 3200),
                    HistoryBand(date: day(0), value: 3050, lower: 2900, upper: 3200)]
        let balance = HistorySeries.energyBalance(intake: intake, tdee: tdee, calendar: cal)
        #expect(balance.count == 2)
        #expect(balance[0].value == -550)     // deficit
        #expect(balance[1].value == 150)      // surplus
    }

    /// A day with no logged food must be absent, not a huge fake deficit.
    @Test func energyBalanceSkipsDaysMissingEitherSide() {
        let intake = [HistoryPoint(date: day(0), value: 2500)]
        let tdee = [HistoryBand(date: day(-5), value: 3050, lower: 2900, upper: 3200)]
        #expect(HistorySeries.energyBalance(intake: intake, tdee: tdee, calendar: cal).isEmpty)
    }

    // MARK: Rate of change

    @Test func rateOfChangeTracksTheKnownSlope() {
        let records = (0..<40).map { i in
            DailyRecord(date: day(-39 + i), intakeKcal: 2500,
                        weightKg: 85 - Double(i) * (0.5 / 7))
        }
        let points = HistorySeries.rateOfChange(records: records, prior: prior,
                                                from: day(-2), to: day(0), calendar: cal)
        let latest = try? #require(points.last?.value)
        if let latest { #expect(abs(latest - (-0.5)) < 0.02) }
    }

    /// Weigh-ins alone are enough — the rate doesn't need food logged.
    @Test func rateOfChangeWorksWithoutIntake() {
        let records = (0..<30).map { i in
            DailyRecord(date: day(-29 + i), intakeKcal: nil, weightKg: 85 - Double(i) * 0.05)
        }
        #expect(!HistorySeries.rateOfChange(records: records, prior: prior,
                                            from: day(-3), to: day(0), calendar: cal).isEmpty)
    }

    @Test func guardrailsMatchTheCalorieTargetClamp() {
        let rails = HistorySeries.rateGuardrails(bodyweightKg: 82)
        #expect(abs(rails.loss - (-0.82)) < 0.001)     // 1% of bodyweight
        #expect(abs(rails.gain - 0.41) < 0.001)        // 0.5% of bodyweight
    }

    // MARK: Adherence

    @Test func adherencePairsProteinWithThatDaysTarget() {
        let protein = [day(-1): 160.0, day(0): 120.0]
        let target = [day(-1): 164.0, day(0): 150.0]
        let points = HistorySeries.proteinAdherence(dailyProtein: protein,
                                                    dailyTarget: target, calendar: cal)
        #expect(points.count == 2)
        #expect(points[0].hit)          // 160 of 164
        #expect(!points[1].hit)         // 120 of 150
    }

    /// Tolerance covers rounding, not a real shortfall.
    @Test func adherenceToleranceAcceptsNearMissesOnly() {
        func hit(_ actual: Double, _ target: Double) -> Bool {
            HistorySeries.AdherencePoint(date: day(0), actual: actual, target: target).hit
        }
        #expect(hit(150, 150))
        #expect(hit(149, 150))
        #expect(hit(143, 150))
        #expect(!hit(142, 150))
        #expect(!hit(135, 150))
    }

    @Test func adherenceDropsDaysWithNoTarget() {
        let points = HistorySeries.proteinAdherence(dailyProtein: [day(0): 150],
                                                    dailyTarget: [:], calendar: cal)
        #expect(points.isEmpty)
    }

    @Test func hitRateCountsProportionOfDays() {
        let points = [
            HistorySeries.AdherencePoint(date: day(-3), actual: 160, target: 150),
            HistorySeries.AdherencePoint(date: day(-2), actual: 100, target: 150),
            HistorySeries.AdherencePoint(date: day(-1), actual: 150, target: 150),
            HistorySeries.AdherencePoint(date: day(0), actual: 90, target: 150),
        ]
        #expect(HistorySeries.hitRate(points) == 0.5)
        #expect(HistorySeries.hitRate([]) == nil)
    }

    // MARK: Cardio distance

    private func cardioRecords() -> [CardioDistanceRecord] {
        [
            .init(date: day(-20), activity: .running, distanceMetres: 5_000),
            .init(date: day(-10), activity: .running, distanceMetres: 8_000),
            .init(date: day(-30), activity: .running, distanceMetres: 3_000),
            .init(date: day(-5), activity: .poolSwimming, distanceMetres: 1_500),
            .init(date: day(-3), activity: .running, distanceMetres: 0),      // no distance
            .init(date: day(-100), activity: .running, distanceMetres: 9_000), // out of range
        ]
    }

    @Test func distanceTrendFiltersSortsAndDropsZeroAndOutOfRange() {
        let points = HistorySeries.distanceTrend(cardioRecords(), activity: .running,
                                                 from: day(-40), to: day(0))
        #expect(points.map(\.value) == [3_000, 5_000, 8_000])
        #expect(points.map(\.date) == [day(-30), day(-20), day(-10)])
    }

    @Test func distanceTrendIsActivitySpecific() {
        let points = HistorySeries.distanceTrend(cardioRecords(), activity: .poolSwimming,
                                                 from: day(-40), to: day(0))
        #expect(points.map(\.value) == [1_500])
    }

    @Test func loggedDistanceActivitiesRankByFrequencyAndExcludeEmpty() {
        let activities = HistorySeries.loggedDistanceActivities(cardioRecords(),
                                                                from: day(-40), to: day(0))
        // Running (3 distance-bearing sessions in range) before swimming (1);
        // the 0 m run adds no running count.
        #expect(activities == [.running, .poolSwimming])
    }
}

// `@retroactive` because `HistoryPoint` belongs to the app module, not the test
// one: without it the compiler warns that the owner adding `Equatable` later
// would silently change behaviour here.
extension HistoryPoint: @retroactive Equatable {
    public static func == (a: HistoryPoint, b: HistoryPoint) -> Bool {
        a.date == b.date && a.value == b.value
    }
}
