import Foundation

/// Per-100 g nutrient values resolved from any source (OFF, USDA, custom).
struct NutrientProfile: Sendable, Equatable {
    var kcal: Double = 0
    var proteinG: Double = 0
    var carbsG: Double = 0
    var fatG: Double = 0
    var fibreG: Double = 0
    var micros: [String: Double] = [:]
}

struct ResolvedFood: Sendable, Identifiable {
    let id: String                 // stable natural key: barcode / fdc id / uuid
    let source: FoodSource
    let name: String
    let brand: String?
    let per100g: NutrientProfile
    /// Common serving size in grams if the source provides one.
    let servingGrams: Double?
}

extension ResolvedFood {
    func scaled(grams: Double) -> NutrientProfile {
        let f = grams / 100
        return NutrientProfile(kcal: per100g.kcal * f,
                               proteinG: per100g.proteinG * f,
                               carbsG: per100g.carbsG * f,
                               fatG: per100g.fatG * f,
                               fibreG: per100g.fibreG * f)
    }
}
