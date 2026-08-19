import Testing
import Foundation
@testable import SuperFit

/// Regressions for the defects found in the QA review. Each test names the
/// behaviour that was wrong so a future refactor can't quietly restore it.
struct QARegressionTests {

    // MARK: 1 — recommendation must agree with the score the user sees

    @Test func recommendationBandsMatchTheRoundedScore() {
        // Construct inputs landing just under a band edge so raw and rounded differ.
        for asleep in stride(from: 300, through: 540, by: 5) {
            let result = RecoveryEngine().evaluate(
                RecoveryInputs(asleepMinutes: asleep, sleepEfficiency: 0.93))
            let expected: TrainingRecommendation
            switch result.score {
            case 90...: expected = .pushIntensity
            case 70..<90: expected = .normalTraining
            case 50..<70: expected = .reduceVolume
            default: expected = .recoveryFocus
            }
            #expect(result.recommendation == expected,
                    "score \(result.score) gave \(result.recommendation)")
        }
    }

    // MARK: 2 — macros must not overspend the calorie target

    @Test func macrosNeverExceedTheCalorieTarget() {
        let calc = MacroCalculator()
        for bw in stride(from: 45.0, through: 150.0, by: 5) {
            for goal in FitnessGoal.allCases {
                for kcal in stride(from: 1200.0, through: 3500.0, by: 100) {
                    let t = calc.targets(kcal: kcal, goal: goal, bodyweightKg: bw)
                    // Allow only rounding slack (each macro rounds to 1 g).
                    #expect(t.macroKcal <= kcal + 20 || hitsFloors(t, bw: bw),
                            "bw \(bw) goal \(goal) kcal \(kcal) → \(t.macroKcal)")
                }
            }
        }
    }

    /// The one legitimate overshoot: the target is below the sum of the
    /// physiological floors, which MetabolismEngine's BMR floor prevents.
    private func hitsFloors(_ t: MacroTargets, bw: Double) -> Bool {
        t.carbG <= MacroCalculator.carbFloorG
            && t.fatG <= (MacroCalculator.essentialFatPerKg * bw).rounded()
    }

    @Test func theReviewsFailingCaseNowBalances() {
        let t = MacroCalculator().targets(kcal: 1760, goal: .fatLoss, bodyweightKg: 120)
        #expect(abs(t.macroKcal - 1760) <= 20)   // was 2024 — 264 kcal over
    }

    // MARK: 3 — bodyweight work must register as training load

    @Test func bodyweightExercisesProduceLoad() {
        let id = UUID()
        let day = Date()
        let pullUps = (0..<3).map {
            LiftRecord(date: day.addingTimeInterval(Double($0)), exerciseID: id,
                       weightKg: 0, reps: 8, isWarmup: false, bodyweightFraction: 1.0)
        }
        let window = DateInterval(start: day.addingTimeInterval(-60), end: day.addingTimeInterval(60))
        let load = VolumeAggregator().tonnage(records: pullUps, in: window, bodyweightKg: 80)
        #expect(load == 3 * 8 * 80)      // was 0
    }

    @Test func addedWeightStacksOnBodyweight() {
        let r = LiftRecord(date: Date(), exerciseID: UUID(), weightKg: 20, reps: 5,
                           isWarmup: false, bodyweightFraction: 1.0)
        #expect(r.effectiveLoadKg(bodyweightKg: 80) == 100)
    }

    @Test func externallyLoadedLiftsIgnoreBodyweight() {
        let r = LiftRecord(date: Date(), exerciseID: UUID(), weightKg: 100, reps: 5,
                           isWarmup: false)
        #expect(r.effectiveLoadKg(bodyweightKg: 80) == 100)
    }

    /// Isometric holds: no reps, so no rep-based tonnage by design. Named
    /// explicitly rather than pattern-matched, so adding one is a decision.
    private static let isometricHolds: Set<String> = [
        "Plank", "Side Plank", "Hollow Hold",
    ]

    /// Loaded lifts that also move you. A dumbbell split squat is your bodyweight
    /// on one leg plus the dumbbells; scoring only the dumbbells would badly
    /// under-read the effort.
    private static let loadedButAlsoBodyweight: Set<String> = [
        "Bulgarian Split Squat", "Split Squat", "Walking Lunge", "Reverse Lunge",
        "Step-Up", "Curtsy Lunge",
    ]

    @Test func everyBodyweightCatalogEntryCarriesAFraction() {
        for e in ExerciseLibrary.catalog where e.category == .bodyweight {
            if Self.isometricHolds.contains(e.name) {
                #expect(e.bodyweight == 0, "\(e.name) is a hold and should carry no fraction")
                continue
            }
            #expect(e.bodyweight > 0, "\(e.name) would score zero training load")
        }
        for e in ExerciseLibrary.catalog where e.category != .bodyweight {
            #expect(e.bodyweight == 0 || Self.loadedButAlsoBodyweight.contains(e.name),
                    "\(e.name) unexpectedly carries a bodyweight fraction")
        }
    }

    // MARK: 4 — unknown sleep efficiency must not read as zero

    @Test func unknownEfficiencyDoesNotPenaliseSleep() {
        let known = RecoveryEngine().evaluate(
            RecoveryInputs(asleepMinutes: 480, sleepEfficiency: 0.9))
        let unknown = RecoveryEngine().evaluate(
            RecoveryInputs(asleepMinutes: 480, sleepEfficiency: nil))
        #expect(known.score == unknown.score)

        // A real zero would cost 30% of the component — prove they differ.
        let zeroed = RecoveryEngine().evaluate(
            RecoveryInputs(asleepMinutes: 480, sleepEfficiency: 0))
        #expect(zeroed.score < unknown.score)
    }

    // MARK: 6 — targets must never fall below basal rate

    @Test func calorieTargetNeverGoesBelowBMR() {
        let engine = MetabolismEngine()
        let est = TDEEEstimate(tdeeKcal: 1450, confidence: 0.9, trendSlopeKgPerWeek: -0.3,
                               avgIntakeKcal: 1300, smoothedWeightKg: 50, windowDays: 30,
                               basalKcal: 1180)
        let target = engine.calorieTarget(tdee: est, goal: .fatLoss, bodyweightKg: 50)
        #expect(target >= 1180)
    }

    @Test func calorieFloorFallsBackWhenBMRUnknown() {
        let engine = MetabolismEngine()
        let est = TDEEEstimate(tdeeKcal: 1300, confidence: 0.9, trendSlopeKgPerWeek: -0.3,
                               avgIntakeKcal: 1200, smoothedWeightKg: 45, windowDays: 30)
        #expect(engine.calorieTarget(tdee: est, goal: .fatLoss, bodyweightKg: 45) >= 1200)
    }

    // MARK: 7 — gaps are discounted only where a day-of-week effect is *shown*

    private func makeRecords(cal: Calendar, end: Date,
                             logged: (Int) -> Bool,
                             intake: (Int) -> Double) -> [DailyRecord] {
        (0..<28).map { i in
            let date = cal.date(byAdding: .day, value: -27 + i, to: end)!
            return DailyRecord(date: date,
                               intakeKcal: logged(i) ? intake(i) : nil,
                               weightKg: 80 - Double(i) * 0.02)
        }
    }

    private var testPrior: MetabolismEngine.Prior {
        .init(sex: .male, ageYears: 30, heightCm: 180, activity: .moderate)
    }

    /// No day of the week is special. Which days are missing must not change the
    /// estimate — only how many.
    @Test func gapPatternDoesNotAffectTheEstimate() {
        let cal = Calendar(identifier: .gregorian)
        let end = cal.startOfDay(for: Date())
        let engine = MetabolismEngine()
        let flat: (Int) -> Double = { _ in 2500 }

        // Same count of logged days, different weekdays missing.
        let missingWeekends = engine.estimate(
            records: makeRecords(cal: cal, end: end, logged: { $0 % 7 < 5 }, intake: flat),
            windowDays: 28, prior: testPrior, asOf: end)
        let missingMidweek = engine.estimate(
            records: makeRecords(cal: cal, end: end,
                                 logged: { $0 % 7 != 2 && $0 % 7 != 3 }, intake: flat),
            windowDays: 28, prior: testPrior, asOf: end)

        #expect(missingWeekends.confidence == missingMidweek.confidence)
        #expect(missingWeekends.tdeeKcal == missingMidweek.tdeeKcal)
    }

    /// Unlogged days are filled from the intake trend, so the intake average
    /// covers the same span as the weight slope it is differenced against.
    @Test func unloggedDaysAreImputedFromTheTrend() {
        let cal = Calendar(identifier: .gregorian)
        let end = cal.startOfDay(for: Date())
        let engine = MetabolismEngine()
        // Intake climbs 20 kcal/day: 2200 → 2740 over 28 days, mean ≈ 2470.
        let rising: (Int) -> Double = { 2200 + 20 * Double($0) }

        // First week unlogged. A flat average of the rest sits ~70 kcal high.
        let est = engine.estimate(
            records: makeRecords(cal: cal, end: end, logged: { $0 >= 7 }, intake: rising),
            windowDays: 28, prior: testPrior, asOf: end)

        let trueMean = (0..<28).map(rising).reduce(0, +) / 28
        let flatMean = (7..<28).map(rising).reduce(0, +) / 21
        #expect(abs(est.avgIntakeKcal - trueMean) < abs(flatMean - trueMean))
    }

    /// …but a trend that can't be distinguished from noise is not projected.
    @Test func noiseIsNotMistakenForATrend() {
        let cal = Calendar(identifier: .gregorian)
        let end = cal.startOfDay(for: Date())
        let engine = MetabolismEngine()
        // Deterministic jitter around 2500, no underlying drift.
        let jitter: (Int) -> Double = { 2500 + Double([-160, 90, -40, 170, -110, 60, 20][$0 % 7]) }

        let est = engine.estimate(
            records: makeRecords(cal: cal, end: end, logged: { $0 >= 7 }, intake: jitter),
            windowDays: 28, prior: testPrior, asOf: end)
        let observedMean = (7..<28).map(jitter).reduce(0, +) / 21
        // Falls back to the flat mean of what was logged.
        #expect(abs(est.avgIntakeKcal - observedMean) < 2)
    }

    // MARK: 12 — the weight trend must not bridge long gaps

    @Test func trendResetsAfterALongGap() {
        let day = 86_400.0
        var dates: [Date] = []
        var t = Date(timeIntervalSince1970: 0)
        for _ in 0..<5 { dates.append(t); t = t.addingTimeInterval(day) }
        t = t.addingTimeInterval(90 * day)
        for _ in 0..<3 { dates.append(t); t = t.addingTimeInterval(day) }
        let values = Array(repeating: 80.0, count: 5) + Array(repeating: 90.0, count: 3)

        let timed = TrendFill.ewma(values, dates: dates)
        let indexed = TrendFill.ewma(values)
        // Index-based smoothing drags the stale 80 kg into the post-gap reading.
        #expect(indexed[5] < 85)
        #expect(abs(timed[5] - 90) < 0.5)
    }

    // MARK: 17 — ACWR band boundaries

    @Test func acwrBoundaryIsUnambiguous() {
        func score(acute: Double, chronic: Double) -> Double {
            RecoveryEngine().evaluate(
                RecoveryInputs(acuteLoad: acute, chronicLoad: chronic)).score
        }
        // 1.3 sits in the optimal band, 1.5 in the penalised one.
        #expect(score(acute: 130, chronic: 100) == 100)
        #expect(score(acute: 149, chronic: 100) == 70)
    }
}
