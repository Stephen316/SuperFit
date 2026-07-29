import Testing
import Foundation
@testable import SuperFit

/// Results are ranked by how local the product is. Which API returned it carries
/// no weight — these tests exist to keep it that way, because the previous
/// behaviour buried every British supermarket product under 50 US entries purely
/// because USDA was concatenated first.
struct FoodRelevanceTests {

    private func food(_ id: String, source: FoodSource = .openFoodFacts,
                      countries: [String] = [], generic: Bool = false)
    -> ResolvedFood {
        var f = ResolvedFood(id: id, source: source, name: id, brand: nil,
                             per100g: NutrientProfile(kcal: 100), servingGrams: nil)
        f.countryTags = countries
        f.isGeneric = generic
        return f
    }

    /// Defaults to an empty query so the provenance tests below stay about
    /// provenance: with no term every result ties on name and the band decides.
    private func order(_ foods: [ResolvedFood], query: String = "",
                       region: FoodRegion? = .unitedKingdom,
                       own: Set<String> = []) -> [String] {
        FoodRelevance.ordered(foods, query: query, region: region,
                              ownIDs: own).map(\.id)
    }

    // MARK: Locality beats source

    /// The point of the whole thing: a Tesco product from Open Food Facts must
    /// outrank a US product from USDA, even though USDA is queried first.
    @Test func localRetailBeatsForeignRetailRegardlessOfSource() {
        let result = order([
            food("us-usda", source: .usda, countries: ["united-states"]),
            food("tesco-off", countries: ["united-kingdom"]),
        ])
        #expect(result == ["tesco-off", "us-usda"])
    }

    /// And the reverse: a UK product held by USDA must outrank a US product held
    /// by Open Food Facts. Neither source is preferred.
    @Test func theRankingIsSymmetricAcrossSources() {
        let result = order([
            food("us-off", countries: ["united-states"]),
            food("uk-usda", source: .usda, countries: ["united-kingdom"]),
        ])
        #expect(result == ["uk-usda", "us-off"])
    }

    // MARK: Band order

    @Test func fullBandOrderIsOwnGenericLocalNeighbourForeign() {
        let result = order([
            food("foreign", countries: ["spain"]),
            food("local", countries: ["united-kingdom"]),
            food("neighbour", countries: ["ireland"]),
            food("generic", source: .usda, generic: true),
            food("mine", countries: ["spain"]),
        ], own: ["mine"])
        #expect(result == ["mine", "generic", "local", "neighbour", "foreign"])
    }

    /// Generics outrank even the local shelf: most logging is of ingredients
    /// rather than specific packets, and the lab-analysed generic entries carry
    /// better data than a crowd-sourced branded one.
    @Test func genericWholeFoodsOutrankLocalRetail() {
        let result = order([
            food("tesco-rice", countries: ["united-kingdom"]),
            food("plain-rice", source: .usda, generic: true),
        ])
        #expect(result == ["plain-rice", "tesco-rice"])
    }

    @Test func genericWholeFoodsOutrankForeignRetail() {
        let result = order([
            food("walmart", source: .usda, countries: ["united-states"]),
            food("plain-rice", source: .usda, generic: true),
        ])
        #expect(result == ["plain-rice", "walmart"])
    }

    /// A generic that a source happens to tag with a country must not be pulled
    /// down into a retail band by it.
    @Test func aGenericWithACountryTagStaysGeneric() {
        let result = order([
            food("local-brand", countries: ["united-kingdom"]),
            food("tagged-generic", source: .usda,
                 countries: ["united-states"], generic: true),
        ])
        #expect(result == ["tagged-generic", "local-brand"])
    }

    /// Foods already logged rank first: having eaten something is the strongest
    /// relevance signal available, and it's local by construction.
    @Test func yourOwnFoodsComeFirstEvenWhenForeign() {
        let result = order([
            food("generic", source: .usda, generic: true),
            food("local", countries: ["united-kingdom"]),
            food("previously-logged", countries: ["japan"]),
        ], own: ["previously-logged"])
        #expect(result == ["previously-logged", "generic", "local"])
    }

    @Test func customFoodsCountAsYourOwnWithoutBeingInTheCache() {
        let result = order([
            food("generic", source: .usda, generic: true),
            food("my-recipe", source: .custom),
        ])
        #expect(result == ["my-recipe", "generic"])
    }

    // MARK: Stability

    /// Within a band each source's own relevance order must survive — reordering
    /// there would discard the ranking the APIs already did.
    @Test func orderWithinABandIsPreserved() {
        let result = order([
            food("uk-1", countries: ["united-kingdom"]),
            food("uk-2", countries: ["united-kingdom"]),
            food("uk-3", countries: ["united-kingdom"]),
        ])
        #expect(result == ["uk-1", "uk-2", "uk-3"])
    }

    /// Identical searches must not reshuffle, so the sort can't rely on Swift's
    /// undocumented stability.
    @Test func repeatedOrderingIsIdentical() {
        let foods = [
            food("a", countries: ["spain"]),
            food("b", countries: ["united-kingdom"]),
            food("c", source: .usda, generic: true),
            food("d", countries: ["ireland"]),
            food("e", countries: ["spain"]),
        ]
        let first = order(foods)
        for _ in 0..<20 { #expect(order(foods) == first) }
    }

    // MARK: Degradation

    /// With no country chosen there's no notion of local, so the only meaningful
    /// split left is generic versus retail — and nothing is dropped.
    @Test func withNoRegionGenericsStillLead() {
        let result = order([
            food("retail", countries: ["spain"]),
            food("generic", source: .usda, generic: true),
        ], region: nil)
        #expect(result == ["generic", "retail"])
    }

    /// A product whose source never said where it's sold is unattributed, not
    /// foreign-by-assumption — but it also can't be claimed as local.
    @Test func productsWithNoCountryAreNotAssumedLocal() {
        let result = order([
            food("unknown-origin"),
            food("local", countries: ["united-kingdom"]),
        ])
        #expect(result == ["local", "unknown-origin"])
    }

    @Test func orderingNeverAddsOrLosesResults() {
        let foods = [
            food("a", countries: ["united-kingdom"]),
            food("b", countries: ["ireland"]),
            food("c", source: .usda, generic: true),
            food("d", countries: ["united-states"]),
        ]
        let result = FoodRelevance.ordered(foods, query: "", region: .unitedKingdom,
                                           ownIDs: [])
        #expect(result.count == foods.count)
        #expect(Set(result.map(\.id)) == Set(foods.map(\.id)))
    }

    // MARK: Provenance plumbing

    /// Open Food Facts prefixes tags with a language code; stored without it so a
    /// tag compares directly against FoodRegion.tag.
    @Test func openFoodFactsCountryTagsAreStrippedOfTheLanguagePrefix() {
        #expect(OFFCountryTag.strip(["en:united-kingdom", "fr:france"])
                == ["united-kingdom", "france"])
        #expect(OFFCountryTag.strip(["ireland"]) == ["ireland"])
        #expect(OFFCountryTag.strip(nil).isEmpty)
    }

    @Test func usdaGenericDataTypesAreRecognised() {
        #expect(USDAClient.genericDataTypes.contains("Foundation"))
        #expect(USDAClient.genericDataTypes.contains("SR Legacy"))
        #expect(USDAClient.genericDataTypes.contains("Survey (FNDDS)"))
        #expect(!USDAClient.genericDataTypes.contains("Branded"))
    }

    /// An absent or unrecognised market leaves the food unattributed rather than
    /// asserting a country it never claimed.
    @Test func usdaMarketCountryMapsOntoOpenFoodFactsTags() {
        #expect(USDAClient.countryTags(forMarket: "United States") == ["united-states"])
        #expect(USDAClient.countryTags(forMarket: "united kingdom") == ["united-kingdom"])
        #expect(USDAClient.countryTags(forMarket: nil).isEmpty)
        #expect(USDAClient.countryTags(forMarket: "Atlantis").isEmpty)
    }
}
