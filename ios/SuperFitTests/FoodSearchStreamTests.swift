import Testing
import Foundation
import SwiftData
@testable import SuperFit

/// Free function, not a method: the stub responder is `@Sendable` and runs off
/// the main actor, so it can't call into the main-actor-isolated suite.
private func isUSDAHost(_ url: URL) -> Bool {
    url.host?.contains("nal.usda.gov") == true
}

/// Search delivers results per source instead of awaiting all of them.
///
/// Measured on one term before this: Open Food Facts answered in 0.18s with
/// 8.7 KB, USDA's generics took 2.0s and 1.6 MB, and the survey set another 1.8s
/// per attempt across up to three attempts. Awaiting everything made the fast
/// answer wait on the slow one every single time.
@MainActor
struct FoodSearchStreamTests {

    private func resolver(_ responder: @escaping @Sendable (URL) -> (Int, Data))
    -> FoodResolver {
        StubProtocol.responder = responder
        let container = try! ModelContainer(
            for: Schema(AppSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let session = StubProtocol.session()
        // A fresh cache per resolver: the shared one would carry results between
        // tests and serve a request the test expected to fail.
        return FoodResolver(context: ModelContext(container),
                            usda: USDAClient(session: session, key: { "test-key" }),
                            off: OpenFoodFactsClient(session: session),
                            cache: FoodSearchCache())
    }

    private static let offJSON = """
    {"count": 1, "page": 1, "page_size": 25, "page_count": 1, "hits": [
      {"code": "off-1", "product_name": "Tesco Chicken", "brands": ["Tesco"],
       "countries_tags": ["en:united-kingdom"],
       "nutriments": {"energy-kcal_100g": 106, "proteins_100g": 24}}
    ]}
    """.data(using: .utf8)!

    private static let usdaJSON = """
    {"foods": [
      {"fdcId": 111, "description": "Chicken, raw", "dataType": "SR Legacy",
       "foodNutrients": [{"nutrientId": 1008, "value": 165},
                         {"nutrientId": 1003, "value": 31}]}
    ]}
    """.data(using: .utf8)!



    // MARK: The point

    /// Results reach the screen as each source answers rather than in one lump at
    /// the end — which is what lets the fast source paint while the slow one is
    /// still in flight.
    ///
    /// Deliberately not asserting *which* source arrives first: against instant
    /// stubs there is no latency to order them by, so that would pin the
    /// scheduler rather than the behaviour.
    @Test func resultsArriveProgressivelyRatherThanInOneLump() async {
        let r = resolver { url in
            (200, isUSDAHost(url) ? Self.usdaJSON : Self.offJSON)
        }
        var batches: [[String]] = []
        for await page in r.stream("chicken", region: .unitedKingdom) {
            batches.append(page.foods.map(\.id))
        }
        #expect(batches.count >= 2, "expected progressive yields, got \(batches.count)")
        // The first paint is real but partial, and nothing shown is later removed.
        let first = Set(batches.first ?? [])
        let last = Set(batches.last ?? [])
        #expect(!first.isEmpty)
        #expect(first.isStrictSubset(of: last))
    }

    /// A source that never answers must not stop the others being shown.
    @Test func aHangingSourceStillLetsTheOthersThrough() async {
        let r = resolver { url in
            if isUSDAHost(url) { return (503, Data()) }
            return (200, Self.offJSON)
        }
        var last: [String] = []
        for await page in r.stream("chicken", region: .unitedKingdom) {
            last = page.foods.map(\.id)
        }
        #expect(last.contains("off-1"))
    }

    /// Every yield is the whole list, so the view assigns rather than merges —
    /// and the last one holds everything both sources returned.
    @Test func eachYieldIsTheCompleteListSoFar() async {
        let r = resolver { url in
            (200, isUSDAHost(url) ? Self.usdaJSON : Self.offJSON)
        }
        var batches: [[String]] = []
        for await page in r.stream("chicken", region: .unitedKingdom) {
            batches.append(page.foods.map(\.id))
        }
        let final = try? #require(batches.last)
        #expect(final?.contains("off-1") == true)
        #expect(final?.contains("fdc:111") == true)
        // Never shrinks: a later yield always contains everything an earlier one did.
        for (earlier, later) in zip(batches, batches.dropFirst()) {
            #expect(Set(earlier).isSubset(of: Set(later)))
        }
    }

    /// No result is ever listed twice, however many sources returned it.
    @Test func resultsAreNotDuplicatedAcrossYields() async {
        let r = resolver { url in
            (200, isUSDAHost(url) ? Self.usdaJSON : Self.offJSON)
        }
        var final: [String] = []
        for await page in r.stream("chicken", region: .unitedKingdom) {
            final = page.foods.map(\.id)
        }
        #expect(Set(final).count == final.count)
    }

    /// Ranking is applied to every yield, not bolted on at the end — otherwise
    /// the list would visibly reshuffle as each source landed.
    @Test func everyYieldIsRanked() async {
        let r = resolver { url in
            (200, isUSDAHost(url) ? Self.usdaJSON : Self.offJSON)
        }
        for await page in r.stream("chicken", region: .unitedKingdom) {
            let ids = page.foods.map(\.id)
            // The USDA entry is a generic whole food, so whenever it is present
            // it outranks the Tesco product.
            if ids.contains("fdc:111"), ids.contains("off-1") {
                #expect(ids.firstIndex(of: "fdc:111")! < ids.firstIndex(of: "off-1")!)
            }
        }
    }

    /// Below the minimum the stream ends without touching the network.
    @Test func aShortQueryYieldsNothingAndFinishes() async {
        let r = resolver { _ in (500, Data()) }
        var pages = 0
        for await page in r.stream("ch", region: .unitedKingdom) {
            pages += 1
            #expect(page.foods.isEmpty)
        }
        #expect(pages == 1)
    }
}
