import Foundation

/// One ingredient resolved against the food it points at.
struct MealIngredient: Sendable, Identifiable {
    let itemID: UUID
    let foodID: UUID
    let name: String
    let brand: String?
    let servingGrams: Double
    let per100g: NutrientProfile

    var id: UUID { itemID }
    var total: NutrientProfile { NutrientProfile.scaled(per100g, grams: servingGrams) }
}

/// Turns a saved meal's stored items into ingredients and totals.
///
/// Pure, so meal maths is testable without a store — and so the "ingredient's
/// food was deleted" case is handled in one place rather than in every view that
/// displays a meal.
enum MealComposer {

    /// Ingredients whose food still exists. A `SavedMealItem` points at a `Food`
    /// by id, and foods are deletable from search, so a dangling reference is a
    /// normal state rather than corruption — it's dropped, and `missingCount`
    /// reports how many so the UI can say so instead of silently under-counting.
    static func ingredients(items: [(id: UUID, foodID: UUID?, grams: Double)],
                            foods: [UUID: (name: String, brand: String?, per100g: NutrientProfile)])
    -> (resolved: [MealIngredient], missingCount: Int) {
        var out: [MealIngredient] = []
        var missing = 0
        for item in items {
            guard let foodID = item.foodID, let food = foods[foodID] else {
                missing += 1
                continue
            }
            out.append(MealIngredient(itemID: item.id, foodID: foodID,
                                      name: food.name, brand: food.brand,
                                      servingGrams: item.grams, per100g: food.per100g))
        }
        return (out, missing)
    }

    static func total(_ ingredients: [MealIngredient]) -> NutrientProfile {
        ingredients.reduce(into: NutrientProfile()) { sum, ingredient in
            let t = ingredient.total
            sum.kcal += t.kcal
            sum.proteinG += t.proteinG
            sum.carbsG += t.carbsG
            sum.fatG += t.fatG
            sum.fibreG += t.fibreG
            for (key, value) in t.micros { sum.micros[key, default: 0] += value }
        }
    }
}

extension NutrientProfile {
    /// Scales a per-100 g profile to a gram weight. Shared so meals, foods and
    /// supplements can't drift apart on rounding.
    static func scaled(_ per100g: NutrientProfile, grams: Double) -> NutrientProfile {
        let f = grams / 100
        return NutrientProfile(kcal: per100g.kcal * f,
                               proteinG: per100g.proteinG * f,
                               carbsG: per100g.carbsG * f,
                               fatG: per100g.fatG * f,
                               fibreG: per100g.fibreG * f,
                               micros: per100g.micros.mapValues { $0 * f })
    }
}
