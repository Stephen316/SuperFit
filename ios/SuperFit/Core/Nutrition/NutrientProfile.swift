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

/// A named household measure and what it weighs — "1 medium" at 118 g,
/// "1 cup, sliced" at 150 g. From USDA's `foodPortions`.
struct FoodPortion: Sendable, Codable, Hashable, Identifiable {
    let label: String
    let gramWeight: Double

    var id: String { "\(label)|\(gramWeight)" }
    var display: String { "\(label) (\(Int(gramWeight.rounded())) g)" }
}

struct ResolvedFood: Sendable, Identifiable {
    let id: String                 // stable natural key: barcode / fdc id / uuid
    let source: FoodSource
    let name: String
    let brand: String?
    let per100g: NutrientProfile
    /// Common serving size in grams if the source provides one.
    let servingGrams: Double?
    /// Household measures, when the source lists them. Empty is normal —
    /// branded items usually carry only `servingGrams`.
    var portions: [FoodPortion] = []
}

/// A unit the user can log in: a named portion, grams, or ounces.
struct ServingOption: Sendable, Identifiable, Hashable {
    let label: String
    /// Grams contributed by one of this unit.
    let gramsPerUnit: Double

    var id: String { "\(label)|\(gramsPerUnit)" }

    static let gram = ServingOption(label: "g", gramsPerUnit: 1)
    static let ounce = ServingOption(label: "oz", gramsPerUnit: 28.349523125)

    /// Portions first — they're what people actually think in — then the raw
    /// weight units. Grams and ounces are always offered so nothing is
    /// unloggable when a source has no portion data.
    static func options(for food: ResolvedFood) -> [ServingOption] {
        var out = food.portions.map {
            ServingOption(label: $0.display, gramsPerUnit: $0.gramWeight)
        }
        // A branded serving with no household name still deserves one tap.
        if out.isEmpty, let serving = food.servingGrams, serving > 0 {
            out.append(ServingOption(label: "1 serving (\(Int(serving.rounded())) g)",
                                     gramsPerUnit: serving))
        }
        return out + [.gram, .ounce]
    }
}

extension ResolvedFood {
    func scaled(grams: Double) -> NutrientProfile {
        let f = grams / 100
        return NutrientProfile(kcal: per100g.kcal * f,
                               proteinG: per100g.proteinG * f,
                               carbsG: per100g.carbsG * f,
                               fatG: per100g.fatG * f,
                               fibreG: per100g.fibreG * f,
                               micros: per100g.micros.mapValues { $0 * f })
    }
}
