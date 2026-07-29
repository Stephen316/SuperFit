import Testing
import Foundation
@testable import SuperFit

/// Searching "rice" returned rice cakes, rice vinegar and Rice Krispies with no
/// actual rice in sight. Provenance can't fix that — they're all equally British
/// and equally retail — so the name has to be read.
struct FoodNameMatchTests {

    private func match(_ name: String, _ query: String,
                       brand: String? = nil) -> FoodNameMatch {
        FoodNameMatch.match(name: name, brand: brand, query: query)
    }

    // MARK: The reported case

    /// The whole point, stated as the bug: every rice must outrank every non-rice
    /// whose name merely starts with the word.
    @Test func everyRiceOutranksEveryThingNamedAfterRice() {
        let rices = ["Rice", "Rice, white, long-grain, cooked", "Brown Rice",
                     "Basmati Rice", "Tesco Long Grain White Rice"]
        let notRices = ["Rice Cakes", "Rice Krispies", "Rice Vinegar",
                        "Rice Pudding", "Rice Noodles"]
        for rice in rices {
            for notRice in notRices {
                #expect(match(rice, "rice") < match(notRice, "rice"),
                        "\"\(rice)\" should outrank \"\(notRice)\"")
            }
        }
    }

    // MARK: Head-last, the English rule

    @Test func theLastWordIsTheFood() {
        #expect(match("Brown Rice", "rice") == .headNoun)
        #expect(match("Basmati Rice", "rice") == .headNoun)
        #expect(match("Semi Skimmed Milk", "milk") == .headNoun)
        #expect(match("Dark Chocolate", "chocolate") == .headNoun)
    }

    /// The same word leading instead of trailing names a different food, and this
    /// is the distinction that was missing.
    @Test func aLeadingWordQualifiesSomethingElse() {
        #expect(match("Rice Cakes", "rice") == .modifier)
        #expect(match("Milk Chocolate", "milk") == .modifier)
        #expect(match("Chocolate Cake", "chocolate") == .modifier)
        #expect(match("Chicken Soup", "chicken") == .modifier)
    }

    // MARK: Head-first with commas, the USDA rule

    @Test func usdaQualifiersAfterTheCommaAreIgnored() {
        #expect(match("Rice, white, long-grain, regular, cooked", "rice") == .exact)
        #expect(match("Milk, whole, 3.25% milkfat", "milk") == .exact)
        #expect(match("Chicken, broilers or fryers, breast, raw", "chicken") == .exact)
    }

    /// After a comma the word is the qualifier, not the food: "Cereal, rice" is a
    /// cereal. Read as head-last it would wrongly look like a rice, so the
    /// head-noun test deliberately never sees past the first comma.
    @Test func aWordAfterTheCommaDoesNotMakeItTheFood() {
        #expect(match("Cereal, rice", "rice") == .modifier)
        #expect(match("Cereals ready-to-eat, KELLOGG, RICE KRISPIES", "rice")
                == .modifier)
    }

    @Test func exactNamesAreExact() {
        #expect(match("Rice", "rice") == .exact)
        #expect(match("rice", "RICE") == .exact)
        #expect(match("Chicken Breast", "chicken breast") == .exact)
    }

    // MARK: Multi-word queries

    @Test func theWordsMustBeAdjacentNotMerelyPresent() {
        // Both words appear, but not as the thing being searched for.
        #expect(match("Chicken Soup with Breast Meat", "chicken breast") == .partial)
        #expect(match("Free Range Chicken Breast", "chicken breast") == .headNoun)
    }

    @Test func aQueryWithNoWordsInCommonDoesNotMatch() {
        #expect(match("Rice Cakes", "chocolate") == .none)
        #expect(match("Whole Milk", "beef wellington") == .none)
    }

    // MARK: Punctuation and looser matches

    /// The catalogues disagree about hyphens and apostrophes, so both sides fold
    /// to the same tokens.
    @Test func punctuationDoesNotChangeTheMatch() {
        #expect(match("Rice, white, long-grain", "long grain rice") == .partial)
        #expect(match("Sainsbury's Basmati Rice", "sainsburys rice") == .partial)
        #expect(match("Long-Grain Rice", "rice") == .headNoun)
    }

    /// Inside a longer word still counts, but only just — it ranks below every
    /// real match rather than being dropped.
    @Test func aWordInsideALongerWordIsAPartialMatch() {
        #expect(match("Riced Cauliflower", "rice") == .partial)
    }

    /// Open Food Facts keeps the brand out of the product name, so a search that
    /// names the shop has to look there too.
    @Test func theBrandIsSearchableEvenThoughItIsNotInTheName() {
        #expect(match("Long Grain Rice", "tesco rice", brand: "Tesco") == .partial)
        #expect(match("Long Grain Rice", "tesco rice") == .none)
    }

    // MARK: Degradation

    /// A store chip browses a whole range with no term. Everything must tie so
    /// provenance decides, exactly as it did before name matching existed.
    @Test func anEmptyQueryTiesEverything() {
        #expect(match("Rice Cakes", "") == .exact)
        #expect(match("Anything At All", "   ") == .exact)
    }

    @Test func theBandsAreOrderedBestFirst() {
        #expect(FoodNameMatch.exact < FoodNameMatch.headNoun)
        #expect(FoodNameMatch.headNoun < FoodNameMatch.modifier)
        #expect(FoodNameMatch.modifier < FoodNameMatch.partial)
        #expect(FoodNameMatch.partial < FoodNameMatch.none)
    }
}
