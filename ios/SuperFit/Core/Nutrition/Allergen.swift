import Foundation

/// The allergens a label must declare.
///
/// These fourteen are the set EU and UK law requires to be declared on
/// packaging (Regulation 1169/2011, which Ireland follows), and they are also
/// what Open Food Facts tags against — so the user's list and the data speak
/// the same vocabulary without a mapping table in between.
enum Allergen: String, CaseIterable, Identifiable, Codable, Sendable {
    case gluten, crustaceans, eggs, fish, peanuts, soybeans, milk
    case nuts, celery, mustard, sesame, sulphites, lupin, molluscs

    var id: String { rawValue }

    var label: String {
        switch self {
        case .gluten: return "Cereals containing gluten"
        case .crustaceans: return "Crustaceans"
        case .eggs: return "Eggs"
        case .fish: return "Fish"
        case .peanuts: return "Peanuts"
        case .soybeans: return "Soybeans"
        case .milk: return "Milk"
        case .nuts: return "Tree nuts"
        case .celery: return "Celery"
        case .mustard: return "Mustard"
        case .sesame: return "Sesame"
        case .sulphites: return "Sulphites"
        case .lupin: return "Lupin"
        case .molluscs: return "Molluscs"
        }
    }

    /// What the label usually calls it, for the picker's second line.
    var examples: String {
        switch self {
        case .gluten: return "Wheat, barley, rye, oats, spelt"
        case .crustaceans: return "Prawns, crab, lobster"
        case .eggs: return "Egg, albumen, mayonnaise"
        case .fish: return "Fish, anchovy, fish sauce"
        case .peanuts: return "Peanut, groundnut, arachis"
        case .soybeans: return "Soya, tofu, edamame"
        case .milk: return "Milk, butter, cheese, whey, lactose"
        case .nuts: return "Almond, hazelnut, walnut, cashew, pistachio"
        case .celery: return "Celery, celeriac"
        case .mustard: return "Mustard seed, mustard powder"
        case .sesame: return "Sesame seed, tahini"
        case .sulphites: return "Sulphur dioxide, E220–E228"
        case .lupin: return "Lupin flour, lupin seed"
        case .molluscs: return "Mussels, squid, oyster, snail"
        }
    }

    /// Open Food Facts `allergens_tags` values with the language prefix
    /// stripped. More than one where OFF has not settled on a single spelling.
    var offTags: Set<String> {
        switch self {
        case .gluten: return ["gluten"]
        case .crustaceans: return ["crustaceans"]
        case .eggs: return ["eggs"]
        case .fish: return ["fish"]
        case .peanuts: return ["peanuts"]
        case .soybeans: return ["soybeans"]
        case .milk: return ["milk"]
        case .nuts: return ["nuts"]
        case .celery: return ["celery"]
        case .mustard: return ["mustard"]
        case .sesame: return ["sesame-seeds", "sesame"]
        case .sulphites: return ["sulphur-dioxide-and-sulphites", "sulphites"]
        case .lupin: return ["lupin"]
        case .molluscs: return ["molluscs"]
        }
    }

    /// Words that withhold a "safe" verdict when they appear in the ingredient
    /// text but no tag was raised.
    ///
    /// Deliberately loose, and deliberately unable to *assert* an allergen:
    /// "coconut milk" trips `milk` without being dairy, so a hit here downgrades
    /// the food to unknown rather than declaring it unsafe.
    var keywords: [String] {
        switch self {
        case .gluten: return ["wheat", "barley", "rye", "spelt", "gluten", "semolina"]
        case .crustaceans: return ["prawn", "shrimp", "crab", "lobster", "crustace"]
        case .eggs: return ["egg", "albumen", "mayonnaise"]
        case .fish: return ["fish", "anchov", "cod", "tuna", "salmon"]
        case .peanuts: return ["peanut", "groundnut", "arachis"]
        case .soybeans: return ["soy", "soja", "tofu", "edamame"]
        case .milk: return ["milk", "butter", "cheese", "whey", "lactose", "cream", "lait"]
        case .nuts: return ["almond", "hazelnut", "walnut", "cashew", "pistachio",
                            "pecan", "macadamia", "noisette"]
        case .celery: return ["celery", "celeriac"]
        case .mustard: return ["mustard", "moutarde"]
        case .sesame: return ["sesame", "tahini"]
        case .sulphites: return ["sulphite", "sulfite", "sulphur dioxide", "sulfur dioxide"]
        case .lupin: return ["lupin"]
        case .molluscs: return ["mussel", "squid", "oyster", "snail", "clam", "mollusc"]
        }
    }
}

/// What can be said about one food against the allergens a user avoids.
enum AllergenStatus: Sendable, Equatable {
    /// The source published enough to judge by, and none of them appear.
    case safe
    /// Declared on the label, by tag. Only ever from a tag, never from a guess.
    case contains(Set<Allergen>)
    /// Nothing published, or published but contradicted by the ingredient text.
    /// The only honest answer for most of the catalogue.
    case unknown
}

/// Decides whether a food can be called safe for the allergens someone avoids.
///
/// The whole point is the third state. Roughly a third of Open Food Facts
/// products carry no allergen tags at all, and USDA publishes none, so a design
/// that only said "safe" or "contains" would call most of the catalogue safe by
/// default — the one failure that matters here. Absence of a tag is never taken
/// as absence of an allergen.
enum AllergenCheck {
    static func status(allergenTags: [String], traceTags: [String],
                       ingredientsText: String?,
                       avoiding: Set<Allergen>) -> AllergenStatus {
        guard !avoiding.isEmpty else { return .unknown }

        let declared = Set(allergenTags.map(normalise) + traceTags.map(normalise))
        let hits = avoiding.filter { !$0.offTags.isDisjoint(with: declared) }
        if !hits.isEmpty { return .contains(hits) }

        let ingredients = (ingredientsText ?? "").lowercased()
        // Tags alone are not evidence of a *reading*: a product with neither
        // tags nor an ingredient list has simply never been transcribed.
        guard !declared.isEmpty || !ingredients.isEmpty else { return .unknown }

        // The tagger missed something the text mentions, so no claim is made.
        let mentioned = avoiding.contains { allergen in
            allergen.keywords.contains { ingredients.contains($0) }
        }
        return mentioned ? .unknown : .safe
    }

    /// `en:milk` and `Milk` both arrive; the tag body is what carries meaning.
    private static func normalise(_ tag: String) -> String {
        let body = tag.contains(":") ? String(tag.split(separator: ":").last ?? "") : tag
        return body.trimmingCharacters(in: .whitespaces).lowercased()
    }
}

/// The allergens the user has said they avoid, kept as one string so the
/// preference needs no model and no schema migration.
enum AvoidedAllergens {
    static let storageKey = "avoidedAllergens"

    static func decode(_ raw: String) -> Set<Allergen> {
        Set(raw.split(separator: ",").compactMap { Allergen(rawValue: String($0)) })
    }

    /// Sorted so the stored string is stable and two devices writing the same
    /// selection produce the same value.
    static func encode(_ allergens: Set<Allergen>) -> String {
        allergens.map(\.rawValue).sorted().joined(separator: ",")
    }
}
