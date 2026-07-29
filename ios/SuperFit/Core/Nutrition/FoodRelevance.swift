import Foundation

/// Orders search results by how local the *product* is, not by which API returned
/// it.
///
/// The sources have no standing of their own. USDA happens to hold the lab
/// generics and Open Food Facts happens to hold British supermarket own-brands,
/// but that's an accident of who catalogued what — it says nothing about which
/// result the person searching wants. Ranking by source put up to 50 USDA entries,
/// mostly US branded items, above every Tesco product for a UK user.
///
/// So the key is provenance:
///
/// 1. **Your own foods** — logged before, or created by hand. Not a source
///    preference: a food you've eaten is the strongest relevance signal there is,
///    and it's local by construction.
/// 2. **Generic whole foods** — "rice, white, long-grain, cooked". No supplier, so
///    no country, and deliberately ranked above every branded product. Two
///    reasons: most logging is of ingredients rather than specific packets, and
///    the generic entries are the *better data* — Foundation and SR Legacy are
///    lab-analysed with full micronutrient profiles, where a crowd-sourced branded
///    entry often carries macros alone.
/// 3. **Sold in your country** — the shelf you actually shop from, for when you do
///    want the specific packet.
/// 4. **Sold in a neighbouring country** — the same chains often span both.
/// 5. **Everything else** — foreign retailers.
///
/// The sort is **stable**, so within a band each source's own relevance order
/// survives. This only decides which band a result lands in.
enum FoodRelevance {

    /// Lower sorts earlier.
    enum Band: Int, Comparable, Sendable {
        case ownFood = 0
        case generic = 1
        case localRetail = 2
        case neighbourRetail = 3
        case foreignRetail = 4

        static func < (a: Band, b: Band) -> Bool { a.rawValue < b.rawValue }
    }

    static func band(for food: ResolvedFood, region: FoodRegion?,
                     ownIDs: Set<String>) -> Band {
        if ownIDs.contains(food.id) || food.source == .custom { return .ownFood }
        // Checked before the country bands: a generic outranks retail wherever it
        // happens to be catalogued, so its country — if a source even gives it
        // one — must not pull it down into a retail band.
        if food.isGeneric { return .generic }

        guard let region else {
            // With no country chosen there's no notion of local, so the only
            // meaningful split left is the generic one already made above.
            return .foreignRetail
        }

        if food.countryTags.contains(region.tag) { return .localRetail }
        if !food.countryTags.isEmpty,
           !Set(food.countryTags).isDisjoint(with: Set(region.neighbourTags)) {
            return .neighbourRetail
        }
        return .foreignRetail
    }

    /// Reorders results by band, preserving each source's ordering within a band.
    ///
    /// `sorted(by:)` is not documented as stable in Swift, so the index is carried
    /// as an explicit tiebreak rather than relied on — without it, results would
    /// reshuffle between identical searches.
    static func ordered(_ foods: [ResolvedFood], region: FoodRegion?,
                        ownIDs: Set<String>) -> [ResolvedFood] {
        // Written out rather than chained: the fluent version tips the type
        // checker over its time limit on the tuple.
        struct Ranked {
            let position: Int
            let band: Band
            let food: ResolvedFood
        }

        var ranked: [Ranked] = []
        ranked.reserveCapacity(foods.count)
        for (position, food) in foods.enumerated() {
            let band = band(for: food, region: region, ownIDs: ownIDs)
            ranked.append(Ranked(position: position, band: band, food: food))
        }

        ranked.sort { a, b in
            if a.band != b.band { return a.band < b.band }
            return a.position < b.position
        }
        return ranked.map(\.food)
    }
}
