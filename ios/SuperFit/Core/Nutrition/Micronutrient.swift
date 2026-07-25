import Foundation

/// Micronutrients and health markers tracked alongside macros. Raw values are
/// the short keys used in the bundled FDC seed.
enum Micronutrient: String, CaseIterable, Sendable {
    case saturatedFat = "sat"
    case sugar = "sug"
    case cholesterol = "chl"
    case sodium = "na"
    case potassium = "kp"
    case calcium = "ca"
    case iron = "fe"
    case magnesium = "mg"
    case zinc = "zn"
    case vitaminC = "vc"
    case vitaminD = "vd"
    case vitaminA = "va"
    case vitaminB12 = "b12"
    case folate = "fol"

    var displayName: String {
        switch self {
        case .saturatedFat: return "Saturated fat"
        case .sugar: return "Sugar"
        case .cholesterol: return "Cholesterol"
        case .sodium: return "Sodium"
        case .potassium: return "Potassium"
        case .calcium: return "Calcium"
        case .iron: return "Iron"
        case .magnesium: return "Magnesium"
        case .zinc: return "Zinc"
        case .vitaminC: return "Vitamin C"
        case .vitaminD: return "Vitamin D"
        case .vitaminA: return "Vitamin A"
        case .vitaminB12: return "Vitamin B12"
        case .folate: return "Folate"
        }
    }

    var unit: String {
        switch self {
        case .saturatedFat, .sugar: return "g"
        case .cholesterol, .sodium, .potassium, .calcium, .iron, .magnesium, .zinc, .vitaminC:
            return "mg"
        case .vitaminD, .vitaminA, .vitaminB12, .folate: return "µg"
        }
    }

    /// Whether the target is a floor to reach or a ceiling to stay under.
    var isLimit: Bool {
        switch self {
        case .saturatedFat, .sugar, .cholesterol, .sodium: return true
        default: return false
        }
    }

    var group: Group {
        switch self {
        case .saturatedFat, .sugar, .cholesterol, .sodium: return .limits
        case .potassium, .calcium, .iron, .magnesium, .zinc: return .minerals
        case .vitaminC, .vitaminD, .vitaminA, .vitaminB12, .folate: return .vitamins
        }
    }

    enum Group: String, CaseIterable, Sendable {
        case limits, minerals, vitamins
        var displayName: String {
            switch self {
            case .limits: return "Watch these"
            case .minerals: return "Minerals"
            case .vitamins: return "Vitamins"
            }
        }
    }
}
