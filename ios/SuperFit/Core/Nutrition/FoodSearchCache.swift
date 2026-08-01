import Foundation

/// Recently fetched search results, kept decoded.
///
/// Retyping a term, backspacing, closing and reopening the picker, or switching
/// between the diary and a meal builder all re-ran the same requests. Each USDA
/// leg is roughly a second and a half of latency and 1.6 MB of JSON to parse
/// (162 KB gzipped on the wire), so repeating one is expensive twice over.
///
/// Holding *decoded* results rather than leaning on `URLCache` skips the parse as
/// well as the request, and — more importantly — makes the expiry ours. Neither
/// USDA nor Open Food Facts sends any cache header, so the HTTP cache can only
/// guess, and the session's `returnCacheDataElseLoad` was guessing "forever":
/// once a term was fetched, that answer stood for the life of the cache, and a
/// transiently bad response stood with it.
@MainActor
final class FoodSearchCache {
    static let shared = FoodSearchCache()

    /// Long enough that a session of logging never refetches, short enough that a
    /// product added to Open Food Facts this morning is findable this evening.
    static let ttl: TimeInterval = 6 * 3600

    /// Entries, not bytes: a page is at most ~50 results and the values are
    /// structs of numbers and short strings. Forty covers a long logging session
    /// without holding a meaningful amount of memory.
    static let capacity = 40

    struct Key: Hashable {
        let leg: String
        let query: String
        let page: Int
        let region: String
        let brand: String

        init(leg: String, query: String, page: Int,
             region: FoodRegion?, brand: StoreBrand?) {
            self.leg = leg
            // Case and surrounding space don't change what the APIs return, so
            // "Chicken " and "chicken" should share an entry.
            self.query = query.trimmingCharacters(in: .whitespaces).lowercased()
            self.page = page
            self.region = region?.code ?? ""
            self.brand = brand?.tag ?? ""
        }
    }

    private struct Entry {
        let foods: [ResolvedFood]
        let hasMore: Bool
        let storedAt: Date
    }

    private var entries: [Key: Entry] = [:]
    /// Least-recently-used first, so eviction drops the coldest entry.
    private var recency: [Key] = []
    private let now: () -> Date

    init(now: @escaping () -> Date = Date.init) { self.now = now }

    func value(for key: Key) -> (foods: [ResolvedFood], hasMore: Bool)? {
        guard let entry = entries[key] else { return nil }
        guard now().timeIntervalSince(entry.storedAt) < Self.ttl else {
            // Expired entries are dropped on read rather than swept: a stale one
            // that is never asked for again costs nothing.
            entries[key] = nil
            recency.removeAll { $0 == key }
            return nil
        }
        touch(key)
        return (entry.foods, entry.hasMore)
    }

    func store(_ foods: [ResolvedFood], hasMore: Bool, for key: Key) {
        // An empty result is not cached. A source that returned nothing is more
        // often a blip than a fact, and caching it would hide the food for hours.
        guard !foods.isEmpty else { return }
        entries[key] = Entry(foods: foods, hasMore: hasMore, storedAt: now())
        touch(key)
        while recency.count > Self.capacity, let coldest = recency.first {
            entries[coldest] = nil
            recency.removeFirst()
        }
    }

    func removeAll() {
        entries.removeAll()
        recency.removeAll()
    }

    private func touch(_ key: Key) {
        recency.removeAll { $0 == key }
        recency.append(key)
    }
}
