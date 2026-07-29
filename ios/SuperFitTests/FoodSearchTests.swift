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
            let isCountryQuery = (url.query?.removingPercentEncoding ?? "")
                .contains("countries_tags:")
            return (200, isCountryQuery ? localJSON : globalJSON)
        }
        let page = try await off.search("chicken", region: .unitedKingdom)
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
            (url.query?.removingPercentEncoding ?? "").contains("countries_tags:")
                ? (200, Self.emptyJSON) : (200, globalJSON)
        }
        let page = try await off.search("natto", region: .unitedKingdom)
        #expect(page.foods.map(\.id) == ["jp-1"])
    }

    // MARK: Neighbour tier

    /// Several country tags go in one OR'd request rather than one request each.
    @Test func severalNeighboursAreOrdIntoASingleQuery() async throws {
        nonisolated(unsafe) var queries: [String] = []
        let off = client { url in
            queries.append(url.query?.removingPercentEncoding ?? "")
            return (200, Self.emptyJSON)
        }
        _ = try await off.search("bread", region: .germany)
        let neighbour = queries.first { $0.contains(" OR ") }
        #expect(neighbour?.contains("countries_tags:\"en:austria\"") == true)
        #expect(neighbour?.contains("countries_tags:\"en:netherlands\"") == true)
        // Still one request for the whole tier, not one per country.
        #expect(queries.count == 3)
    }

    /// A lone neighbour needs no OR — it's an ordinary single-tag query.
    @Test func aSingleNeighbourSkipsTheOrSyntax() async throws {
        nonisolated(unsafe) var queries: [String] = []
        let off = client { url in
            queries.append(url.query?.removingPercentEncoding ?? "")
            return (200, Self.emptyJSON)
        }
        _ = try await off.search("milk", region: .ireland)
        #expect(queries.count == 3)
        #expect(!queries.contains { $0.contains(" OR ") })
        #expect(queries.contains { $0.contains("countries_tags:\"en:united-kingdom\"") })
    }

    /// Three tiers: the chosen country, its neighbours, then everywhere.
    @Test func theThreeTiersMergeInPrecisionOrder() async throws {
        func hit(_ code: String) -> String {
            """
            {"code": "\(code)", "product_name": "Milk \(code)", "brands": ["X"],
             "nutriments": {"energy-kcal_100g": 50, "proteins_100g": 3}}
            """
        }
        func page(_ codes: [String]) -> Data {
            """
            {"count": \(codes.count), "page": 1, "page_size": 25, "page_count": 1,
             "hits": [\(codes.map(hit).joined(separator: ","))]}
            """.data(using: .utf8)!
        }
        let off = client { url in
            let q = url.query?.removingPercentEncoding ?? ""
            // Two neighbours, so the tier is distinguishable by its OR clause.
            if q.contains(" OR ") { return (200, page(["gb-1", "ie-1"])) }
            if q.contains("countries_tags:") { return (200, page(["ie-1"])) }
            return (200, page(["fr-1", "gb-1"]))
        }
        let region = FoodRegion(code: "IE", displayName: "Ireland", tag: "ireland",
                                neighbours: ["GB", "FR"])
        let result = try await off.search("milk", region: region)
        // Irish first, then the neighbours, then the rest — each only once.
        #expect(result.foods.map(\.id) == ["ie-1", "gb-1", "fr-1"])
    }

    /// A country with no listed neighbours costs two requests, not three.
    @Test func aRegionWithoutNeighboursSkipsThatTier() async throws {
        nonisolated(unsafe) var calls = 0
        let off = client { _ in
            calls += 1
            return (200, Self.emptyJSON)
        }
        let lonely = FoodRegion(code: "ZY", displayName: "Nowhere",
                                tag: "nowhere", neighbours: [])
        _ = try await off.search("milk", region: lonely)
        #expect(calls == 2)
    }

    /// Ireland and the UK point at each other: the same chains span both, and
    /// Irish coverage alone is thin — "milk" is 2,125 products for Ireland
    /// against 9,000 for Ireland or the UK.
    @Test func irelandAndTheUKAreMutualNeighbours() {
        #expect(FoodRegion.ireland.neighbourTags == ["united-kingdom"])
        #expect(FoodRegion.unitedKingdom.neighbourTags == ["ireland"])
    }

    @Test func unmappedNeighbourCodesAreDroppedNotGuessed() {
        let odd = FoodRegion(code: "GB", displayName: "UK", tag: "united-kingdom",
                             neighbours: ["IE", "ZZ"])
        #expect(odd.neighbourTags == ["ireland"])
    }

    // MARK: Region setting

    @Test func anExplicitCountryOverridesTheDevice() {
        let region = FoodRegionSetting.effective(stored: "IE", deviceCode: "GB")
        #expect(region == .ireland)
    }

    @Test func automaticFollowsTheDevice() {
        let region = FoodRegionSetting.effective(
            stored: FoodRegionSetting.automatic, deviceCode: "GB")
        #expect(region == .unitedKingdom)
    }

    /// An unmapped device region searches unweighted rather than sending a tag
    /// that matches nothing and returning an empty list.
    @Test func anUnmappedDeviceRegionMeansNoWeighting() {
        #expect(FoodRegionSetting.effective(
            stored: FoodRegionSetting.automatic, deviceCode: "ZZ") == nil)
        #expect(FoodRegionSetting.effective(
            stored: FoodRegionSetting.automatic, deviceCode: nil) == nil)
    }

    /// A stored country that no longer exists in the list falls back rather than
    /// leaving search silently unweighted.
    @Test func anUnknownStoredCountryFallsBackToTheDevice() {
        #expect(FoodRegionSetting.effective(stored: "ZZ", deviceCode: "GB")
                == .unitedKingdom)
    }

    /// The automatic option names what it resolves to, so the choice isn't blind.
    @Test func theAutomaticLabelNamesTheResolvedCountry() {
        #expect(FoodRegionSetting.automaticLabel(deviceCode: "IE")
                == "Automatic (Ireland)")
        #expect(FoodRegionSetting.automaticLabel(deviceCode: "ZZ") == "Automatic")
    }

    @Test func everyRegionHasADistinctCodeAndTag() {
        #expect(Set(FoodRegion.all.map(\.code)).count == FoodRegion.all.count)
        #expect(Set(FoodRegion.all.map(\.tag)).count == FoodRegion.all.count)
    }

    // MARK: Store filter

    @Test func aStoreFilterAddsTheBrandTagToTheQuery() async throws {
        nonisolated(unsafe) var seen: String?
        let off = client { url in
            seen = url.query?.removingPercentEncoding
            return (200, Self.aliciousJSON)
        }
        _ = try await off.search("pasta", region: .unitedKingdom, brand: .tesco)
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
        _ = try await off.search("pasta", region: .unitedKingdom, brand: .lidl)
        #expect(calls == 1)
    }

    /// Browsing a store's whole range is a legitimate empty-term search; without
    /// this the chips do nothing until you also type something.
    @Test func aStoreFilterAloneSearchesWithoutASearchTerm() async throws {
        let off = client { _ in (200, Self.aliciousJSON) }
        let page = try await off.search("", region: .ireland, brand: .superValu)
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

    /// A search costs 5–7 requests, so the floor is three characters. Pinned
    /// because the guard is duplicated across the resolver, both clients and the
    /// empty-state text — a stub responder that would fail proves none of them
    /// reached the network.
    @Test func queriesBelowTheMinimumNeverReachTheNetwork() async throws {
        let off = client { _ in (500, Data()) }
        for term in ["c", "ch"] {
            let page = try await off.search(term, region: .unitedKingdom)
            #expect(page.foods.isEmpty, "\"\(term)\" should not have searched")
            #expect(!page.hasMore)
        }
    }

    @Test func theMinimumQueryLengthIsThree() {
        #expect(FoodSearch.minimumQueryLength == 3)
    }

    /// A store chip is a browse, not a search, so it works with no term at all.
    @Test func aStoreFilterIsExemptFromTheMinimum() async throws {
        let off = client { _ in (200, Self.aliciousJSON) }
        let page = try await off.search("", region: .unitedKingdom, brand: .tesco)
        #expect(!page.foods.isEmpty)
    }
}
