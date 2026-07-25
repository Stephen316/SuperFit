import Testing
import Foundation
@testable import SuperFit

private func targets(sex: BiologicalSex = .male, age: Int = 30, kcal: Double = 2500,
                     goal: FitnessGoal = .maintenance, sessions: Int = 0) -> [Micronutrient: NutrientTarget] {
    let list = NutrientTargets().targets(.init(sex: sex, ageYears: age, kcalTarget: kcal,
                                               goal: goal, sessionsPerWeek: sessions))
    return Dictionary(uniqueKeysWithValues: list.map { ($0.nutrient, $0) })
}

struct NutrientTargetsTests {

    @Test func everyNutrientGetsATarget() {
        let t = targets()
        for nutrient in Micronutrient.allCases {
            #expect(t[nutrient] != nil, "missing target for \(nutrient)")
            #expect(t[nutrient]!.amount > 0)
        }
    }

    /// Reference values that must not drift: NIH adult RDAs.
    @Test func matchesPublishedRDAs() {
        let male = targets(sex: .male)
        #expect(male[.magnesium]!.amount == 420)
        #expect(male[.zinc]!.amount == 11)
        #expect(male[.vitaminC]!.amount == 90)
        #expect(male[.vitaminA]!.amount == 900)
        #expect(male[.vitaminB12]!.amount == 2.4)
        #expect(male[.folate]!.amount == 400)

        let female = targets(sex: .female)
        #expect(female[.magnesium]!.amount == 320)
        #expect(female[.zinc]!.amount == 8)
        #expect(female[.vitaminC]!.amount == 75)
        #expect(female[.vitaminA]!.amount == 700)
    }

    @Test func premenopausalWomenGetHigherIron() {
        #expect(targets(sex: .female, age: 30)[.iron]!.amount == 18)
        #expect(targets(sex: .male, age: 30)[.iron]!.amount == 8)
        // Postmenopausal requirement drops to the male figure.
        #expect(targets(sex: .female, age: 60)[.iron]!.amount == 8)
    }

    @Test func trainingRaisesElectrolytesAndIron() {
        let rest = targets(sessions: 0)
        let train = targets(sessions: 5)
        #expect(train[.sodium]!.amount > rest[.sodium]!.amount)
        #expect(train[.potassium]!.amount > rest[.potassium]!.amount)
        #expect(train[.iron]!.amount > rest[.iron]!.amount)
        #expect(train[.sodium]!.reason != nil)
    }

    @Test func trainingThresholdIsThreeSessions() {
        #expect(targets(sessions: 2)[.sodium]!.amount == 2300)
        #expect(targets(sessions: 3)[.sodium]!.amount == 3000)
    }

    @Test func limitsScaleWithIntake() {
        let low = targets(kcal: 2000)
        let high = targets(kcal: 3000)
        #expect(high[.saturatedFat]!.amount > low[.saturatedFat]!.amount)
        #expect(high[.sugar]!.amount > low[.sugar]!.amount)
        // 10% of energy: 2000 kcal → 200 kcal → 22.2 g fat, 50 g sugar
        #expect(abs(low[.saturatedFat]!.amount - 200.0 / 9) < 0.01)
        #expect(abs(low[.sugar]!.amount - 50) < 0.01)
    }

    @Test func ceilingsAreFlaggedAsLimits() {
        let t = targets()
        for nutrient in [Micronutrient.sodium, .sugar, .saturatedFat, .cholesterol] {
            #expect(t[nutrient]!.isLimit, "\(nutrient) should be a ceiling")
        }
        for nutrient in [Micronutrient.iron, .calcium, .vitaminD, .folate] {
            #expect(!t[nutrient]!.isLimit, "\(nutrient) should be a floor")
        }
    }

    @Test func cuttingRaisesCalciumForBoneProtection() {
        #expect(targets(goal: .maintenance)[.calcium]!.amount == 1000)
        #expect(targets(goal: .fatLoss)[.calcium]!.amount == 1200)
        #expect(targets(goal: .fatLoss)[.calcium]!.reason != nil)
    }

    @Test func olderAdultsGetMoreVitaminD() {
        #expect(targets(age: 40)[.vitaminD]!.amount == 15)
        #expect(targets(age: 60)[.vitaminD]!.amount == 20)
    }

    @Test func olderWomenGetMoreCalcium() {
        #expect(targets(sex: .female, age: 60)[.calcium]!.amount == 1200)
    }
}
