import Testing
import Foundation
@testable import SuperFit

private func food(portions: [FoodPortion] = [], servingGrams: Double? = nil,
                  kcal: Double = 89, protein: Double = 1.09) -> ResolvedFood {
    ResolvedFood(id: "fdc:1", source: .usda, name: "Bananas, raw", brand: nil,
                 per100g: NutrientProfile(kcal: kcal, proteinG: protein,
                                          carbsG: 22.84, fatG: 0.33, fibreG: 2.6,
                                          micros: [Micronutrient.potassium.rawValue: 358]),
                 servingGrams: servingGrams, portions: portions)
}

struct ServingOptionTests {

    // MARK: Options offered

    /// Grams and ounces are always available, so nothing is ever unloggable
    /// just because a source has no portion data.
    @Test func weightUnitsAreAlwaysOffered() {
        let options = ServingOption.options(for: food())
        #expect(options.contains(.gram))
        #expect(options.contains(.ounce))
    }

    @Test func portionsComeFirst() {
        let options = ServingOption.options(for: food(portions: [
            FoodPortion(label: "1 medium", gramWeight: 118),
            FoodPortion(label: "1 cup, sliced", gramWeight: 150),
        ]))
        #expect(options.count == 4)
        #expect(options[0].gramsPerUnit == 118)
        #expect(options[1].gramsPerUnit == 150)
        #expect(options[2] == .gram)
        #expect(options[3] == .ounce)
    }

    /// A branded item with a weight but no household name still gets a one-tap
    /// serving rather than forcing the user to type grams.
    @Test func servingWeightBecomesAnOptionWhenUnnamed() {
        let options = ServingOption.options(for: food(servingGrams: 30))
        #expect(options.count == 3)
        #expect(options[0].gramsPerUnit == 30)
        #expect(options[0].label.contains("30 g"))
    }

    @Test func namedPortionsWinOverTheRawServingWeight() {
        let options = ServingOption.options(
            for: food(portions: [FoodPortion(label: "1 bar", gramWeight: 60)],
                      servingGrams: 60))
        // Only the named portion, not a duplicate generic "1 serving".
        #expect(options.count == 3)
        #expect(options[0].label == "1 bar (60 g)")
    }

    // MARK: Conversion

    @Test func ounceIsTheInternationalAvoirdupoisGram() {
        #expect(abs(ServingOption.ounce.gramsPerUnit - 28.349523125) < 1e-9)
    }

    @Test func quantityTimesUnitGivesGrams() {
        let medium = ServingOption(label: "1 medium (118 g)", gramsPerUnit: 118)
        #expect(2 * medium.gramsPerUnit == 236)
        #expect(abs(3.5 * ServingOption.ounce.gramsPerUnit - 99.22) < 0.01)
        #expect(100 * ServingOption.gram.gramsPerUnit == 100)
    }

    /// The whole point: logging "1 medium banana" must give the nutrients of
    /// 118 g, not of 100 g.
    @Test func portionScalesNutrientsByItsWeightNotPer100g() {
        let banana = food(portions: [FoodPortion(label: "1 medium", gramWeight: 118)])
        let option = ServingOption.options(for: banana)[0]
        let scaled = banana.scaled(grams: 1 * option.gramsPerUnit)

        #expect(abs(scaled.kcal - 89 * 1.18) < 0.01)
        #expect(abs((scaled.micros[Micronutrient.potassium.rawValue] ?? 0) - 358 * 1.18) < 0.01)
    }

    @Test func ounceLoggingMatchesItsGramEquivalent() {
        let banana = food()
        let viaOunces = banana.scaled(grams: 4 * ServingOption.ounce.gramsPerUnit)
        let viaGrams = banana.scaled(grams: 113.398092)
        #expect(abs(viaOunces.kcal - viaGrams.kcal) < 0.001)
    }

    // MARK: Display

    @Test func portionDisplayIncludesItsWeight() {
        #expect(FoodPortion(label: "1 medium", gramWeight: 118).display == "1 medium (118 g)")
        // Weights are rounded for display but not for maths.
        #expect(FoodPortion(label: "1 tbsp", gramWeight: 14.2).display == "1 tbsp (14 g)")
    }

    @Test func optionsAreDistinctForPickerIdentity() {
        let options = ServingOption.options(for: food(portions: [
            FoodPortion(label: "1 medium", gramWeight: 118),
            FoodPortion(label: "1 large", gramWeight: 136),
        ]))
        #expect(Set(options.map(\.id)).count == options.count)
    }
}
