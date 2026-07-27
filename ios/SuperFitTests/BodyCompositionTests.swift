import Testing
import Foundation
@testable import SuperFit

struct BodyCompositionTests {

    private func prior(leanMassKg: Double? = nil) -> MetabolismEngine.Prior {
        .init(sex: .male, ageYears: 30, heightCm: 180, activity: .moderate,
              leanMassKg: leanMassKg)
    }

    /// One weigh-in is enough to read basal out of the estimate.
    private func basal(_ p: MetabolismEngine.Prior, weightKg: Double = 82) -> Double {
        MetabolismEngine().estimate(
            records: [DailyRecord(date: Date().addingTimeInterval(-86_400),
                                  intakeKcal: nil, weightKg: weightKg)],
            windowDays: 30, prior: p).basalKcal
    }

    // MARK: Equation selection

    @Test func mifflinIsUsedWhenLeanMassIsUnknown() {
        // 10(82) + 6.25(180) − 5(30) + 5
        #expect(basal(prior()) == 1800)
    }

    @Test func katchMcArdleIsUsedWhenLeanMassIsKnown() {
        // 370 + 21.6 × 69.7 for 82 kg at 15% body fat
        let lean = 82 * 0.85
        #expect(abs(basal(prior(leanMassKg: lean)) - (370 + 21.6 * lean)) < 1)
    }

    /// Katch drops sex, age and height — lean mass already carries what they
    /// were proxying for. Two very different people with the same lean mass get
    /// the same basal, which is the point of the equation.
    @Test func katchIgnoresSexAgeAndHeight() {
        let lean = 60.0
        let young = MetabolismEngine.Prior(sex: .male, ageYears: 20, heightCm: 190,
                                           activity: .moderate, leanMassKg: lean)
        let older = MetabolismEngine.Prior(sex: .female, ageYears: 55, heightCm: 158,
                                           activity: .moderate, leanMassKg: lean)
        #expect(abs(basal(young) - basal(older)) < 1)
    }

    // MARK: Guards

    @Test func impossibleLeanMassFallsBackToMifflin() {
        // Lean mass above bodyweight is a bad reading, not a lean athlete.
        #expect(basal(prior(leanMassKg: 95), weightKg: 82) == 1800)
        #expect(basal(prior(leanMassKg: 0), weightKg: 82) == 1800)
        #expect(basal(prior(leanMassKg: -5), weightKg: 82) == 1800)
    }

    // MARK: Sensitivity — the reason ranges were rejected

    /// Five points of body-fat error moves basal ~89 kcal, so a self-estimated
    /// bracket carries about as much error as Mifflin it would replace.
    @Test func fivePointsOfBodyFatErrorMovesBasalAboutNinetyKcal() {
        let atFifteen = basal(prior(leanMassKg: 82 * 0.85))
        let atTwenty = basal(prior(leanMassKg: 82 * 0.80))
        #expect(abs((atFifteen - atTwenty) - 88.6) < 1)
    }

    /// Underestimating body fat inflates basal, which raises the calorie floor.
    /// This is the direction that would block a legitimate deficit, and the
    /// reason guessed input is not offered.
    @Test func underestimatingBodyFatRaisesTheCalorieFloor() {
        let engine = MetabolismEngine()
        func target(bodyFat: Double) -> Double {
            let est = engine.estimate(
                records: [DailyRecord(date: Date().addingTimeInterval(-86_400),
                                      intakeKcal: nil, weightKg: 82)],
                windowDays: 30, prior: prior(leanMassKg: 82 * (1 - bodyFat)))
            return engine.calorieTarget(tdee: est, goal: .fatLoss, bodyweightKg: 82)
        }
        // Someone truly 25% who guesses 15% gets a higher floor than the truth.
        #expect(target(bodyFat: 0.15) > target(bodyFat: 0.25))
    }

    // MARK: Protein basis

    /// Lean mass now actually reaches MacroCalculator, so the lean-mass g/kg
    /// values added in the QA pass finally apply.
    @Test func leanMassChangesTheProteinBasis() {
        let calc = MacroCalculator()
        let byWeight = calc.targets(kcal: 2400, goal: .recomposition, bodyweightKg: 82)
        let byLean = calc.targets(kcal: 2400, goal: .recomposition, bodyweightKg: 82,
                                  leanMassKg: 65)
        #expect(byWeight.proteinG == 164)      // 2.0 g/kg bodyweight
        #expect(byLean.proteinG == 156)        // 2.4 g/kg lean mass
    }
}
