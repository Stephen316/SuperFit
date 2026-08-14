import Foundation

/// Per-100 g nutrient values resolved from any source (OFF, USDA, custom).
struct NutrientProfile: Sendable, Equatable {
    var kcal: Double = 0
    var proteinG: Double = 0
    var carbsG: Double = 0
    var fatG: Double = 0
    var fibreG: Double = 0
    /// Water in grams per 100 g (or per 100 ml for a liquid source). nil means
    /// the source did not provide enough information to estimate it safely.
    var waterG: Double? = nil
    var micros: [String: Double] = [:]
}

/// Volume conversions shared by source decoding and the serving picker.
enum FoodVolume {
    static let millilitresPerFluidOunce = 29.5735295625

    static func millilitres(amount: Double, unit: String) -> Double? {
        guard amount > 0 else { return nil }
        let value = unit.lowercased()
            .replacingOccurrences(of: ".", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let factor: Double
        switch value {
        case "ml", "milliliter", "milliliters", "millilitre", "millilitres": factor = 1
        case "cl", "centiliter", "centiliters", "centilitre", "centilitres": factor = 10
        case "l", "liter", "liters", "litre", "litres": factor = 1_000
        case "tsp", "teaspoon", "teaspoons": factor = 4.92892159375
        case "tbsp", "tablespoon", "tablespoons": factor = 14.78676478125
        case "fl oz", "floz", "fluid ounce", "fluid ounces":
            factor = millilitresPerFluidOunce
        case "cup", "cups": factor = 236.5882365
        default: return nil
        }
        return amount * factor
    }

    /// Parses package text such as "250 ml" or "8 fl oz". It deliberately
    /// ignores plain ounces: those are a weight unless explicitly marked fluid.
    static func millilitres(in text: String) -> Double? {
        let pattern = #"([0-9]+(?:[\.,][0-9]+)?)\s*(fluid ounces?|fl\.?\s*oz\.?|floz|millilit(?:er|re)s?|ml|centilit(?:er|re)s?|cl|lit(?:er|re)s?|cups?|tablespoons?|tbsp|teaspoons?|tsp)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let amountRange = Range(match.range(at: 1), in: text),
              let unitRange = Range(match.range(at: 2), in: text),
              let amount = Double(text[amountRange].replacingOccurrences(of: ",", with: "."))
        else { return nil }
        return millilitres(amount: amount, unit: String(text[unitRange]))
    }

    /// Token matching avoids short liquid words causing false positives — for
    /// example, "steak" contains the letters "tea" but is not a drink.
    static func looksLiquid(name: String) -> Bool {
        let tokens = Set(name.lowercased().components(
            separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty })
        let liquidTokens: Set<String> = [
            "drink", "drinks", "beverage", "beverages", "juice", "juices",
            "milk", "milkshake", "smoothie", "smoothies", "shake", "shakes",
            "water", "tea", "coffee", "sauce", "sauces", "dressing", "dressings",
            "syrup", "syrups", "broth", "stock", "soup", "soups",
            "yogurt", "yogurts", "yoghurt", "yoghurts",
        ]
        return !tokens.isDisjoint(with: liquidTokens)
    }
}

/// A named household measure and what it weighs — "1 medium" at 118 g,
/// "1 cup, sliced" at 150 g. From USDA's `foodPortions`.
struct FoodPortion: Sendable, Codable, Hashable, Identifiable {
    let label: String
    let gramWeight: Double
    /// The same portion's volume, when the source supplies a liquid measure.
    /// Optional keeps previously cached portion JSON and backups readable.
    let millilitres: Double?

    init(label: String, gramWeight: Double, millilitres: Double? = nil) {
        self.label = label
        self.gramWeight = gramWeight
        self.millilitres = millilitres
    }

    var id: String { "\(label)|\(gramWeight)|\(millilitres ?? 0)" }
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

    /// Source-provided density. When absent, a volume-labelled portion can
    /// derive it; a conservative 1 g/ml fallback is only used for recognisable,
    /// water-rich drinks and sauces.
    var gramsPerMillilitre: Double? = nil

    /// Open Food Facts `countries_tags` for this product, without the `en:`
    /// prefix — the countries it's actually sold in. Empty when the source
    /// doesn't say, which is not the same as "sold nowhere".
    var countryTags: [String] = []

    /// Declared allergens, and "may contain" separately, without the `en:`
    /// prefix. Empty is "nothing published", never "contains nothing" — see
    /// `AllergenCheck`, which is the only thing allowed to draw that line.
    var allergenTags: [String] = []
    var traceTags: [String] = []

    /// The label's ingredient list, when the source carries one. Used to
    /// withhold a safe verdict the tags would otherwise have allowed.
    var ingredientsText: String? = nil

    /// A whole food rather than a retailer's product: "Rice, white, long-grain,
    /// cooked". Has no country because it has no supplier, so it must not be
    /// ranked as foreign — plain rice is plain rice wherever you buy it.
    var isGeneric: Bool = false
}

/// A unit the user can log in: a named portion, weight, or liquid volume.
struct ServingOption: Sendable, Identifiable, Hashable {
    enum Kind: String, Sendable {
        case portion, gram, ounce, millilitre, fluidOunce
    }

    let label: String
    /// Grams contributed by one of this unit.
    let gramsPerUnit: Double
    /// Volume contributed by one unit, for liquid units and volume portions.
    let millilitresPerUnit: Double?
    let kind: Kind

    init(label: String, gramsPerUnit: Double,
         millilitresPerUnit: Double? = nil, kind: Kind = .portion) {
        self.label = label
        self.gramsPerUnit = gramsPerUnit
        self.millilitresPerUnit = millilitresPerUnit
        self.kind = kind
    }

    var id: String { "\(kind.rawValue)|\(label)|\(gramsPerUnit)|\(millilitresPerUnit ?? 0)" }

    static let gram = ServingOption(label: "g", gramsPerUnit: 1, kind: .gram)
    static let ounce = ServingOption(label: "oz", gramsPerUnit: 28.349523125, kind: .ounce)

    static func millilitre(density: Double) -> ServingOption {
        ServingOption(label: "ml", gramsPerUnit: density,
                      millilitresPerUnit: 1, kind: .millilitre)
    }

    static func fluidOunce(density: Double) -> ServingOption {
        ServingOption(label: "fl oz",
                      gramsPerUnit: density * FoodVolume.millilitresPerFluidOunce,
                      millilitresPerUnit: FoodVolume.millilitresPerFluidOunce,
                      kind: .fluidOunce)
    }

    /// Portions first — they're what people actually think in — then the raw
    /// weight units. Grams and ounces are always offered so nothing is
    /// unloggable when a source has no portion data.
    static func options(for food: ResolvedFood) -> [ServingOption] {
        var out = food.portions.map {
            ServingOption(label: $0.display, gramsPerUnit: $0.gramWeight,
                          millilitresPerUnit: $0.millilitres)
        }
        // A branded serving with no household name still deserves one tap.
        if out.isEmpty, let serving = food.servingGrams, serving > 0 {
            out.append(ServingOption(label: "1 serving (\(Int(serving.rounded())) g)",
                                     gramsPerUnit: serving))
        }
        if let density = food.effectiveGramsPerMillilitre {
            out.append(.millilitre(density: density))
            out.append(.fluidOunce(density: density))
        }
        return out + [.gram, .ounce]
    }
}

extension ResolvedFood {
    var effectiveGramsPerMillilitre: Double? {
        if let gramsPerMillilitre, (0.2...2.5).contains(gramsPerMillilitre) {
            return gramsPerMillilitre
        }
        let measured = portions.compactMap { portion -> Double? in
            guard let volume = portion.millilitres, volume > 0 else { return nil }
            let density = portion.gramWeight / volume
            return (0.2...2.5).contains(density) ? density : nil
        }
        if !measured.isEmpty {
            return measured.sorted()[measured.count / 2]
        }

        guard (per100g.waterG ?? 0) >= 40 else { return nil }
        return FoodVolume.looksLiquid(name: name) ? 1 : nil
    }

    func scaled(grams: Double) -> NutrientProfile {
        let f = grams / 100
        return NutrientProfile(kcal: per100g.kcal * f,
                               proteinG: per100g.proteinG * f,
                               carbsG: per100g.carbsG * f,
                               fatG: per100g.fatG * f,
                               fibreG: per100g.fibreG * f,
                               waterG: per100g.waterG.map { $0 * f },
                               micros: per100g.micros.mapValues { $0 * f })
    }
}
