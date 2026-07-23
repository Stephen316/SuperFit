import Testing
import Foundation
@testable import SuperFit

private let prior = MetabolismEngine.Prior(
    sex: .male, ageYears: 30, heightCm: 180, activity: .moderate)

private func records(days: Int, intake: Double, startWeight: Double,
                     kgPerDay: Double) -> [DailyRecord] {
    let cal = Calendar(identifier: .gregorian)
    let now = cal.startOfDay(for: Date())
    return (0..<days).map { i in
        let date = cal.date(byAdding: .day, value: -(days - 1 - i), to: now)!
        return DailyRecord(date: date, intakeKcal: intake,
                           weightKg: startWeight + kgPerDay * Double(i))
    }
}

@Suite struct MetabolismEngineTests {

    @Test func waterWeightSpikeBarelyMovesTDEE() {
        let e = MetabolismEngine()
        var recs = records(days: 30, intake: 2600, startWeight: 80, kgPerDay: 0)
        // +2 kg glycogen/water spike on the FINAL day — worst case for OLS leverage
        let last = recs.removeLast()
        recs.append(DailyRecord(date: last.date, intakeKcal: last.intakeKcal,
                                weightKg: last.weightKg! + 2))
        let est = e.estimate(records: recs, windowDays: 30, prior: prior)
        #expect(abs(est.tdeeKcal - 2600) < 60)   // Theil–Sen ignores the outlier
    }

    @Test func stableWeightMeansTDEEEqualsIntake() {
        let e = MetabolismEngine()
        let recs = records(days: 30, intake: 2600, startWeight: 80, kgPerDay: 0)
        let est = e.estimate(records: recs, windowDays: 30, prior: prior)
        #expect(abs(est.tdeeKcal - 2600) < 60)          // ≈ intake
        #expect(abs(est.trendSlopeKgPerWeek) < 0.05)
        #expect(est.confidence > 0.6)
    }

    @Test func halfKgPerWeekLossImpliesRoughly550DeficitAboveIntake() {
        let e = MetabolismEngine()
        // −0.5 kg/week = −0.0714 kg/day
        let recs = records(days: 30, intake: 2600, startWeight: 82, kgPerDay: -0.0714)
        let est = e.estimate(records: recs, windowDays: 30, prior: prior)
        // TDEE ≈ 2600 + 550 = 3150; Theil–Sen is exact on a clean trend
        #expect(abs(est.tdeeKcal - 3150) < 30)
        #expect(abs(est.trendSlopeKgPerWeek - (-0.5)) < 0.02)
    }

    @Test func sparseDataLeansOnPriorWithLowConfidence() {
        let e = MetabolismEngine()
        let recs = records(days: 3, intake: 2200, startWeight: 75, kgPerDay: 0)
        let est = e.estimate(records: recs, windowDays: 30, prior: prior)
        #expect(est.confidence < 0.3)
    }

    @Test func measuredActiveEnergyReplacesActivityFactorInPrior() {
        let e = MetabolismEngine()
        let recs = records(days: 3, intake: 2200, startWeight: 80, kgPerDay: 0)
        // Passive BMR for 80 kg male 30y 180cm = 1780. Measured 650 active:
        // prior = (1780 + 650) / 0.9 ≈ 2700, regardless of the activity guess.
        let sedentaryPlusMeasured = MetabolismEngine.Prior(
            sex: .male, ageYears: 30, heightCm: 180,
            activity: .sedentary, avgActiveEnergyKcal: 650)
        let athletePlusMeasured = MetabolismEngine.Prior(
            sex: .male, ageYears: 30, heightCm: 180,
            activity: .athlete, avgActiveEnergyKcal: 650)
        let a = e.estimate(records: recs, windowDays: 30, prior: sedentaryPlusMeasured)
        let b = e.estimate(records: recs, windowDays: 30, prior: athletePlusMeasured)
        #expect(a.tdeeKcal == b.tdeeKcal)          // guess ignored when measured
        #expect(abs(a.tdeeKcal - 2700) < 60)       // sparse data ≈ pure prior
    }

    @Test func calorieTargetRespectsRecompDeficitBand() {
        let e = MetabolismEngine()
        let est = TDEEEstimate(tdeeKcal: 2800, confidence: 0.9,
                               trendSlopeKgPerWeek: 0, avgIntakeKcal: 2800,
                               smoothedWeightKg: 80, windowDays: 30)
        let target = e.calorieTarget(tdee: est, goal: .recomposition, bodyweightKg: 80)
        #expect(target < 2800)                    // deficit
        #expect(target > 2800 * 0.85)             // not more than ~15%
    }

    @Test func fatLossTargetClampedToOnePercentBodyweight() {
        let e = MetabolismEngine()
        let est = TDEEEstimate(tdeeKcal: 2000, confidence: 0.9,
                               trendSlopeKgPerWeek: 0, avgIntakeKcal: 2000,
                               smoothedWeightKg: 60, windowDays: 30)
        // 20% of 2000 = 400 deficit, but 1%/wk of 60 kg = 660 kcal cap → 400 allowed.
        let target = e.calorieTarget(tdee: est, goal: .fatLoss, bodyweightKg: 60)
        let maxDeficit = 60 * 0.01 * MetabolismEngine.kcalPerKg / 7
        #expect(target >= est.tdeeKcal - maxDeficit - 1)
    }
}

@Suite struct TrendFillTests {

    @Test func ewmaStartsAtFirstValueAndDampsSpikes() {
        let smoothed = TrendFill.ewma([80, 80, 80, 82, 80, 80])
        #expect(smoothed[0] == 80)
        #expect(smoothed[3] < 80.5)          // 2 kg spike damped below +0.5
        #expect(smoothed.count == 6)
    }
}

@Suite struct MacroCalculatorTests {

    @Test func proteinFatCarbsSumToCalories() {
        let m = MacroCalculator().targets(kcal: 2400, goal: .recomposition, bodyweightKg: 80)
        let kcalFromMacros = 4 * m.proteinG + 9 * m.fatG + 4 * m.carbG
        #expect(abs(kcalFromMacros - 2400) < 40)
    }

    @Test func proteinInRecompBand() {
        let m = MacroCalculator().targets(kcal: 2400, goal: .recomposition, bodyweightKg: 80)
        #expect(m.proteinG >= 1.6 * 80)
        #expect(m.proteinG <= 2.2 * 80)
    }

    @Test func fatNeverBelowHealthFloor() {
        let m = MacroCalculator().targets(kcal: 1600, goal: .fatLoss, bodyweightKg: 90)
        #expect(m.fatG >= 0.8 * 90 - 1)
    }
}
