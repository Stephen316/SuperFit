import Testing
import Foundation
@testable import SuperFit

/// The search cache holds decoded results with an expiry we control.
///
/// It exists because neither API sends a cache header, so `URLCache` can only
/// guess — and the session was telling it to guess "forever".
@MainActor
struct FoodSearchCacheTests {

    private func food(_ id: String) -> ResolvedFood {
        ResolvedFood(id: id, source: .usda, name: id, brand: nil,
                     per100g: NutrientProfile(kcal: 100), servingGrams: nil)
    }

    private func key(_ query: String, leg: String = "off", page: Int = 1,
                     region: FoodRegion? = .unitedKingdom,
                     brand: StoreBrand? = nil) -> FoodSearchCache.Key {
        .init(leg: leg, query: query, page: page, region: region, brand: brand)
    }

    @Test func storesAndReturnsResults() {
        let cache = FoodSearchCache()
        cache.store([food("a")], hasMore: true, for: key("chicken"))
        let hit = cache.value(for: key("chicken"))
        #expect(hit?.foods.map(\.id) == ["a"])
        #expect(hit?.hasMore == true)
    }

    @Test func aMissReturnsNothing() {
        let cache = FoodSearchCache()
        #expect(cache.value(for: key("chicken")) == nil)
    }

    // MARK: What counts as the same search

    /// Case and stray spaces don't change what the APIs return, so they must not
    /// split the entry — otherwise "Chicken " re-fetches what "chicken" just got.
    @Test func caseAndSurroundingSpaceShareAnEntry() {
        let cache = FoodSearchCache()
        cache.store([food("a")], hasMore: false, for: key("chicken"))
        #expect(cache.value(for: key("  Chicken ")) != nil)
    }

    /// Everything that changes the request must split the entry, or one search
    /// would be served another's results.
    @Test func eachRequestDimensionKeysSeparately() {
        let cache = FoodSearchCache()
        cache.store([food("a")], hasMore: false, for: key("chicken"))
        #expect(cache.value(for: key("chicken", leg: "usda-core")) == nil)
        #expect(cache.value(for: key("chicken", page: 2)) == nil)
        #expect(cache.value(for: key("chicken", region: .ireland)) == nil)
        #expect(cache.value(for: key("chicken", brand: .tesco)) == nil)
    }

    // MARK: Expiry

    @Test func entriesExpireAfterTheTTL() {
        nonisolated(unsafe) var now = Date(timeIntervalSince1970: 0)
        let cache = FoodSearchCache(now: { now })
        cache.store([food("a")], hasMore: false, for: key("chicken"))

        now = now.addingTimeInterval(FoodSearchCache.ttl - 1)
        #expect(cache.value(for: key("chicken")) != nil)

        now = now.addingTimeInterval(2)
        #expect(cache.value(for: key("chicken")) == nil)
    }

    /// A source returning nothing is more often a blip than a fact. Caching it
    /// would hide a food for hours over one failed request.
    @Test func emptyResultsAreNotCached() {
        let cache = FoodSearchCache()
        cache.store([], hasMore: false, for: key("chicken"))
        #expect(cache.value(for: key("chicken")) == nil)
    }

    // MARK: Eviction

    @Test func theColdestEntryIsEvictedFirst() {
        let cache = FoodSearchCache()
        for i in 0...FoodSearchCache.capacity {
            cache.store([food("f\(i)")], hasMore: false, for: key("term\(i)"))
        }
        // One more than capacity was stored, so the first is gone and the last
        // survives.
        #expect(cache.value(for: key("term0")) == nil)
        #expect(cache.value(for: key("term\(FoodSearchCache.capacity)")) != nil)
    }

    /// Reading an entry makes it recent, so a term used throughout a session
    /// isn't evicted by terms typed once.
    @Test func readingAnEntryProtectsItFromEviction() {
        let cache = FoodSearchCache()
        cache.store([food("keep")], hasMore: false, for: key("keeper"))
        for i in 0..<(FoodSearchCache.capacity - 1) {
            cache.store([food("f\(i)")], hasMore: false, for: key("term\(i)"))
            _ = cache.value(for: key("keeper"))
        }
        cache.store([food("last")], hasMore: false, for: key("last"))
        #expect(cache.value(for: key("keeper")) != nil)
    }

    @Test func removeAllClearsEverything() {
        let cache = FoodSearchCache()
        cache.store([food("a")], hasMore: false, for: key("chicken"))
        cache.removeAll()
        #expect(cache.value(for: key("chicken")) == nil)
    }
}
