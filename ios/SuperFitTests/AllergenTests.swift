import Testing
@testable import SuperFit

/// The load-bearing property is that silence is never read as safety. Roughly a
/// third of Open Food Facts products carry no allergen tags and USDA publishes
/// none at all, so a check that defaulted to "safe" would clear most of the
/// catalogue on no evidence.
struct AllergenTests {
    @Test func declaredAllergenIsReported() {
        let status = AllergenCheck.status(
            allergenTags: ["en:milk", "en:nuts"], traceTags: [],
            ingredientsText: "Sugar, hazelnuts, skimmed milk powder",
            avoiding: [.milk])
        #expect(status == .contains([.milk]))
    }

    @Test func tracesCountAsDeclared() {
        let status = AllergenCheck.status(
            allergenTags: [], traceTags: ["en:peanuts"],
            ingredientsText: "Oats, sugar",
            avoiding: [.peanuts])
        #expect(status == .contains([.peanuts]))
    }

    @Test func clearLabelWithIngredientsIsSafe() {
        let status = AllergenCheck.status(
            allergenTags: ["en:gluten"], traceTags: [],
            ingredientsText: "Wheat flour, water, salt, yeast",
            avoiding: [.milk])
        #expect(status == .safe)
    }

    /// The case the whole design exists for: nothing published at all.
    @Test func noPublishedDataIsUnknownNotSafe() {
        let status = AllergenCheck.status(
            allergenTags: [], traceTags: [], ingredientsText: nil,
            avoiding: [.milk])
        #expect(status == .unknown)
    }

    /// A USDA result — nutrients only, no formulation — must never earn a tick.
    @Test func usdaShapedResultIsUnknown() {
        let status = AllergenCheck.status(
            allergenTags: [], traceTags: [], ingredientsText: "",
            avoiding: [.gluten, .milk])
        #expect(status == .unknown)
    }

    /// The tagger missing something the text names withholds the verdict rather
    /// than asserting it, because the keyword alone cannot tell coconut milk
    /// from dairy — it may only take a tick away, never grant one.
    @Test func untaggedMentionDowngradesToUnknown() {
        let status = AllergenCheck.status(
            allergenTags: ["en:soybeans"], traceTags: [],
            ingredientsText: "Coconut milk, rice, salt",
            avoiding: [.milk])
        #expect(status == .unknown)
    }

    @Test func avoidingNothingNeverClaimsSafety() {
        let status = AllergenCheck.status(
            allergenTags: [], traceTags: [],
            ingredientsText: "Wheat flour, water", avoiding: [])
        #expect(status == .unknown)
    }

    @Test func tagsAreMatchedWithoutTheLanguagePrefix() {
        let prefixed = AllergenCheck.status(
            allergenTags: ["en:sesame-seeds"], traceTags: [],
            ingredientsText: "Tahini", avoiding: [.sesame])
        let bare = AllergenCheck.status(
            allergenTags: ["sesame-seeds"], traceTags: [],
            ingredientsText: "Tahini", avoiding: [.sesame])
        #expect(prefixed == .contains([.sesame]))
        #expect(bare == .contains([.sesame]))
    }

    @Test func everyAllergenHasTagsAndKeywords() {
        for allergen in Allergen.allCases {
            #expect(!allergen.offTags.isEmpty)
            #expect(!allergen.keywords.isEmpty)
            #expect(!allergen.label.isEmpty)
            #expect(!allergen.examples.isEmpty)
        }
    }

    @Test func selectionRoundTripsThroughStorage() {
        let set: Set<Allergen> = [.milk, .gluten, .sesame]
        #expect(AvoidedAllergens.decode(AvoidedAllergens.encode(set)) == set)
        #expect(AvoidedAllergens.decode("") == [])
        #expect(AvoidedAllergens.decode("milk,notreal") == [.milk])
    }

    /// Two devices writing the same selection must produce the same string.
    @Test func encodingIsStable() {
        #expect(AvoidedAllergens.encode([.milk, .gluten])
                == AvoidedAllergens.encode([.gluten, .milk]))
    }
}
