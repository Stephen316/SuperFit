import Testing
import Foundation
@testable import SuperFit

/// The search service Open Food Facts moved to returns a different shape from the
/// legacy endpoint, and the country handling has to sort without hiding anything.
struct FoodSearchTests {

    private static let aliciousJSON = """
    {
      "count": 7112,
      "page": 1,
      "page_size": 25,
      "page_count": 3,
      "hits": [
        {
          "code": "5000000000001",
          "product_name": "Chicken Breast Fillets",
          "brands": ["Tesco"],
          "serving_quantity": 125,
          "nutriments": {
            "energy-kcal_100g": 106,
            "proteins_100g": 24.0,
            "carbohydrates_100g": 0.0,
            "fat_100g": 1.1,
            "fiber_100g": 0.0
          }
        },
        {
          "code": "5000000000002",
          "product_name": "No nutriments here",
          "brands": ["Nobody"]
        }
      ]
    }
    """.data(using: .utf8)!

    private static let emptyJSON = """
    {"count": 0, "page": 1, "page_size": 25, "page_count": 0, "hits": []}
    """.data(using: .utf8)!

    private func client(_ responder: @escaping @Sendable (URL) -> (Int, Data))
    -> OpenFoodFactsClient {
        StubProtocol.responder = responder
        return OpenFoodFactsClient(session: StubProtocol.session())
    }

    // MARK: Decoding the new shape

    /// The legacy endpoint returned `brands` as a comma-joined string; this one
    /// returns an array, which is the difference most likely to break silently.
    @Test func brandsDecodeFromAnArray() async throws {
        let off = client { _ in (200, Self.aliciousJSON) }
        let page = try await off.search("chicken breast", region: nil)
        #expect(page.foods.first?.brand == "Tesco")
        #expect(page.foods.first?.name == "Chicken Breast Fillets")
    }

    @Test func servingQuantityDecodesAsANumber() async throws {
        let off = client { _ in (200, Self.aliciousJSON) }
        let page = try await off.search("chicken breast", region: nil)
        #expect(page.foods.first?.servingGrams == 125)
    }

    /// A product with no energy value can't be logged against a calorie target,
    /// so it's dropped rather than shown as 0 kcal.
    @Test func productsWithoutNutrimentsAreDropped() async throws {
        let off = client { _ in (200, Self.aliciousJSON) }
        let page = try await off.search("chicken breast", region: nil)
        #expect(page.foods.count == 1)
    }

    @Test func morePagesAreReportedFromThePageCount() async throws {
        let off = client { _ in (200, Self.aliciousJSON) }
        let page = try await off.search("chicken", region: nil)
        #expect(page.hasMore)
        let last = try await off.search("chicken", page: 3, region: nil)
        #expect(!last.hasMore)
    }

    // MARK: Country sorting

    /// Local results lead, but global ones still follow — a hard filter would
    /// hide anything imported or bought abroad with no way to tell it existed.
    @Test func localResultsLeadWithoutHidingTheRest() async throws {
        let localJSON = """
        {"count": 1, "page": 1, "page_size": 25, "page_count": 1, "hits": [
          {"code": "uk-1", "product_name": "Tesco Chicken", "brands": ["Tesco"],
           "nutriments": {"energy-kcal_100g": 106, "proteins_100g": 24}}
        ]}
        """.data(using: .utf8)!
        let globalJSON = """
        {"count": 2, "page": 1, "page_size": 25, "page_count": 1, "hits": [
          {"code": "es-1", "product_name": "Pollo", "brands": ["Hacendado"],
           "nutriments": {"energy-kcal_100g": 181, "proteins_100g": 17}},
          {"code": "uk-1", "product_name": "Tesco Chicken", "brands": ["Tesco"],
           "nutriments": {"energy-kcal_100g": 106, "proteins_100g": 24}}
        ]}
        """.data(using: .utf8)!

        let off = client { url in
            let isCountryQuery = (url.query ?? "").contains("countries_tags")
            return (200, isCountryQuery ? localJSON : globalJSON)
        }
        let page = try await off.search("chicken", region: "GB")
        #expect(page.foods.map(\.id) == ["uk-1", "es-1"])
    }

    @Test func aRegionWithNoLocalMatchesStillReturnsGlobalOnes() async throws {
        let globalJSON = """
        {"count": 1, "page": 1, "page_size": 25, "page_count": 1, "hits": [
          {"code": "jp-1", "product_name": "Natto", "brands": ["Okame"],
           "nutriments": {"energy-kcal_100g": 212, "proteins_100g": 17}}
        ]}
        """.data(using: .utf8)!
        let off = client { url in
            (url.query ?? "").contains("countries_tags")
                ? (200, Self.emptyJSON) : (200, globalJSON)
        }
        let page = try await off.search("natto", region: "GB")
        #expect(page.foods.map(\.id) == ["jp-1"])
    }

    /// Open Food Facts tags are English country names, not ISO codes.
    @Test func regionCodesMapOntoOpenFoodFactsTags() {
        let off = OpenFoodFactsClient()
        #expect(off.countryTag(for: "GB") == "united-kingdom")
        #expect(off.countryTag(for: "gb") == "united-kingdom")
        #expect(off.countryTag(for: "US") == "united-states")
        #expect(off.countryTag(for: "NZ") == "new-zealand")
    }

    /// An unmapped region searches unweighted rather than sending a tag that
    /// matches nothing and silently returning an empty list.
    @Test func unmappedRegionsFallBackToTheirLowercasedCode() {
        #expect(OpenFoodFactsClient().countryTag(for: "ZZ") == "zz")
    }

    // MARK: Store filter

    @Test func aStoreFilterAddsTheBrandTagToTheQuery() async throws {
        nonisolated(unsafe) var seen: String?
        let off = client { url in
            seen = url.query?.removingPercentEncoding
            return (200, Self.aliciousJSON)
        }
        _ = try await off.search("pasta", region: "GB", brand: .tesco)
        #expect(seen?.contains("brands_tags:\"tesco\"") == true)
    }

    /// Tesco's own brand is British by definition, so country sorting would only
    /// cost a second request for no change in the results.
    @Test func aStoreFilterSkipsTheCountryQuery() async throws {
        nonisolated(unsafe) var calls = 0
        let off = client { _ in
            calls += 1
            return (200, Self.aliciousJSON)
        }
        _ = try await off.search("pasta", region: "GB", brand: .lidl)
        #expect(calls == 1)
    }

    /// Browsing a store's whole range is a legitimate empty-term search; without
    /// this the chips do nothing until you also type something.
    @Test func aStoreFilterAloneSearchesWithoutASearchTerm() async throws {
        let off = client { _ in (200, Self.aliciousJSON) }
        let page = try await off.search("", region: "GB", brand: .superValu)
        #expect(!page.foods.isEmpty)
    }

    @Test func storeTagsAreTheOpenFoodFactsSpellingNotTheShopName() {
        // `sainsbury` returns 141 products against `sainsbury-s`'s 3,345.
        #expect(StoreBrand.sainsburys.tag == "sainsbury-s")
        #expect(StoreBrand.mAndS.tag == "marks-spencer")
        #expect(StoreBrand.traderJoes.tag == "trader-joe-s")
    }

    @Test func regionsOfferTheirOwnRetailers() {
        let ie = StoreBrand.forRegion("IE")
        #expect(ie.contains(.superValu))
        #expect(ie.contains(.dunnes))
        let gb = StoreBrand.forRegion("GB")
        #expect(gb.contains(.tesco))
        #expect(!gb.contains(.superValu))
        // An unknown region offers nothing rather than a misleading list.
        #expect(StoreBrand.forRegion("ZZ").isEmpty)
        #expect(StoreBrand.forRegion(nil).isEmpty)
    }

    // MARK: Failure handling

    @Test func aFailingSearchServiceDoesNotThrowPastTheFallback() async throws {
        let off = client { _ in (503, Data()) }
        await #expect(throws: (any Error).self) {
            try await off.search("chicken", region: nil)
        }
    }

    @Test func shortQueriesNeverReachTheNetwork() async throws {
        let off = client { _ in (500, Data()) }
        let page = try await off.search("c", region: "GB")
        #expect(page.foods.isEmpty)
        #expect(!page.hasMore)
    }
}
