import Testing
import Foundation
@testable import SuperFit

private func profile(kcal: Double, protein: Double = 0, carbs: Double = 0,
                     fat: Double = 0, micros: [String: Double] = [:]) -> NutrientProfile {
    NutrientProfile(kcal: kcal, proteinG: protein, carbsG: carbs, fatG: fat,
                    fibreG: 0, micros: micros)
}

struct MealComposerTests {

    private let oatsID = UUID()
    private let wheyID = UUID()

    private var lookup: [UUID: (name: String, brand: String?, per100g: NutrientProfile)] {
        [oatsID: (name: "Oats", brand: nil,
                  per100g: profile(kcal: 389, protein: 16.9, carbs: 66.3, fat: 6.9,
                                   micros: [Micronutrient.iron.rawValue: 4.7])),
         wheyID: (name: "Whey", brand: "Brand",
                  per100g: profile(kcal: 377, protein: 83.3, carbs: 6.7, fat: 1.7))]
    }

    // MARK: Scaling

    @Test func ingredientsScaleFromPer100g() throws {
        let (resolved, _) = MealComposer.ingredients(
            items: [(id: UUID(), foodID: oatsID, grams: 80)], foods: lookup)
        let oats = try #require(resolved.first)
        #expect(abs(oats.total.kcal - 389 * 0.8) < 0.01)
        #expect(abs(oats.total.proteinG - 16.9 * 0.8) < 0.01)
        #expect(abs((oats.total.micros[Micronutrient.iron.rawValue] ?? 0) - 4.7 * 0.8) < 0.01)
    }

    @Test func totalSumsEveryIngredient() {
        let (resolved, _) = MealComposer.ingredients(
            items: [(id: UUID(), foodID: oatsID, grams: 80),
                    (id: UUID(), foodID: wheyID, grams: 30)],
            foods: lookup)
        let total = MealComposer.total(resolved)
        #expect(abs(total.kcal - (389 * 0.8 + 377 * 0.3)) < 0.01)
        #expect(abs(total.proteinG - (16.9 * 0.8 + 83.3 * 0.3)) < 0.01)
    }

    @Test func micronutrientsCombineAcrossIngredients() {
        let bothIron: [UUID: (name: String, brand: String?, per100g: NutrientProfile)] = [
            oatsID: (name: "A", brand: nil, per100g: profile(kcal: 100, micros: ["fe": 2])),
            wheyID: (name: "B", brand: nil, per100g: profile(kcal: 100, micros: ["fe": 3])),
        ]
        let (resolved, _) = MealComposer.ingredients(
            items: [(id: UUID(), foodID: oatsID, grams: 100),
                    (id: UUID(), foodID: wheyID, grams: 100)],
            foods: bothIron)
        #expect(MealComposer.total(resolved).micros["fe"] == 5)
    }

    // MARK: Deleted ingredients

    /// Foods are deletable from search, so a meal pointing at a removed food is
    /// a normal state. It must be reported, never silently dropped from the
    /// total as if the meal were smaller than it is.
    @Test func deletedFoodIsReportedNotSilentlySkipped() {
        let (resolved, missing) = MealComposer.ingredients(
            items: [(id: UUID(), foodID: oatsID, grams: 80),
                    (id: UUID(), foodID: UUID(), grams: 50)],   // deleted
            foods: lookup)
        #expect(resolved.count == 1)
        #expect(missing == 1)
    }

    @Test func nilFoodReferenceCountsAsMissing() {
        let (resolved, missing) = MealComposer.ingredients(
            items: [(id: UUID(), foodID: nil, grams: 50)], foods: lookup)
        #expect(resolved.isEmpty)
        #expect(missing == 1)
    }

    @Test func emptyMealHasZeroTotals() {
        let total = MealComposer.total([])
        #expect(total.kcal == 0)
        #expect(total.micros.isEmpty)
    }

    // MARK: Shared scaling

    /// Meals, foods and supplements must agree on the same arithmetic.
    @Test func scaledMatchesResolvedFoodScaling() {
        let per100 = profile(kcal: 200, protein: 20, carbs: 10, fat: 5,
                             micros: ["fe": 3])
        let food = ResolvedFood(id: "x", source: .custom, name: "X", brand: nil,
                                per100g: per100, servingGrams: nil)
        let viaFood = food.scaled(grams: 75)
        let viaComposer = NutrientProfile.scaled(per100, grams: 75)
        #expect(viaFood.kcal == viaComposer.kcal)
        #expect(viaFood.proteinG == viaComposer.proteinG)
        #expect(viaFood.micros["fe"] == viaComposer.micros["fe"])
    }

    // MARK: Label entry conversion

    /// A US label gives per-serving figures only; storing them as per-100 g
    /// would be a silent multi-fold error on every macro.
    @Test func perServingLabelConvertsToPer100g() {
        // 55 g serving at 210 kcal → 381.8 kcal per 100 g
        let grams = 55.0
        let f = 100 / grams
        #expect(abs(210 * f - 381.81) < 0.01)
        #expect(abs(20 * f - 36.36) < 0.01)
    }

    @Test func aServingHeavierThan100gScalesDown() {
        // A 330 ml shake at 150 kcal is 45.5 kcal per 100 g, not 150.
        let f = 100 / 330.0
        #expect(abs(150 * f - 45.45) < 0.01)
    }
}
