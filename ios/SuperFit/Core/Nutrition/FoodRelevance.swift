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
/// 1. **Eaten in the last few days.** The strongest signal there is. A food diary
///    is mostly the same foods over and over, so something logged on Tuesday is
///    very likely what's being searched for on Thursday.
/// 2. **Your own foods** — logged at some point, or created by hand. Not a source
///    preference: a food you've eaten is the strongest relevance signal there is,
///    and it's local by construction.
/// 3. **Generic whole foods** — "rice, white, long-grain, cooked". No supplier, so
///    no country, and deliberately ranked above every branded product. Two
///    reasons: most logging is of ingredients rather than specific packets, and
///    the generic entries are the *better data* — Foundation and SR Legacy are
///    lab-analysed with full micronutrient profiles, where a crowd-sourced branded
///    entry often carries macros alone.
/// 4. **Sold in your country** — the shelf you actually shop from, for when you do
///    want the specific packet.
/// 5. **Sold in a neighbouring country** — the same chains often span both.
/// 6. **Everything else** — foreign retailers.
///
/// Recency sits *inside* the name-match tier, not above it. Eating Rice Krispies
/// on Tuesday must not put them above actual rice when searching "rice" on
/// Thursday — that is the exact complaint the name matching was built to fix. So a
/// recent food leads the results that answer the query equally well, and no
/// further.
///
/// Provenance is the **second** key, not the first. It orders foods that answer
/// the query equally well, and can't distinguish a thing from the things named
/// after it — "rice cakes" and "brown rice" are both British, both retail, both
/// contain the word. `FoodNameMatch` makes that call first; everything below then
/// decides between the results that tied.
///
/// The sort is **stable**, so within a band each source's own relevance order
/// survives. This only decides which band a result lands in.
enum FoodRelevance {

    /// Lower sorts earlier.
    enum Band: Int, Comparable, Sendable {
        case recentlyEaten = 0
        case ownFood = 1
        case generic = 2
        case localRetail = 3
        case neighbourRetail = 4
        case foreignRetail = 5

        static func < (a: Band, b: Band) -> Bool { a.rawValue < b.rawValue }
    }

    /// How far back counts as "recently eaten".
    static let recentDays = 5

    static func band(for food: ResolvedFood, region: FoodRegion?,
                     ownIDs: Set<String>, recentIDs: Set<String> = []) -> Band {
        if recentIDs.contains(food.id) { return .recentlyEaten }
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

    /// A result with everything the ordering decided about it, so the picker can
    /// show the categories rather than just inherit their order.
    struct Ranked: Sendable {
        let food: ResolvedFood
        /// How well the name answers the query — the primary sort key.
        let match: FoodNameMatch
        /// How local the product is — decides between equally good name matches.
        let band: Band
        /// Where the sources put it, carried so the sort can't reshuffle.
        let position: Int
    }

    /// Ranks results by name match first, then provenance, then original order.
    ///
    /// `query` is required rather than defaulted: forgetting it would silently
    /// disable the name matching and leave the old behaviour looking correct.
    ///
    /// `sorted(by:)` is not documented as stable in Swift, so the index is carried
    /// as an explicit tiebreak rather than relied on — without it, results would
    /// reshuffle between identical searches.
    static func ranked(_ foods: [ResolvedFood], query: String,
                       region: FoodRegion?, ownIDs: Set<String>,
                       recentIDs: Set<String> = []) -> [Ranked] {
        // Written out rather than chained: the fluent version tips the type
        // checker over its time limit.
        var ranked: [Ranked] = []
        ranked.reserveCapacity(foods.count)
        for (position, food) in foods.enumerated() {
            // Scored once here, never inside the comparator: tokenising is the
            // expensive part, and a comparator would repeat it O(n log n) times.
            let match = FoodNameMatch.match(name: food.name, brand: food.brand,
                                            query: query)
            let band = band(for: food, region: region, ownIDs: ownIDs,
                            recentIDs: recentIDs)
            ranked.append(Ranked(food: food, match: match, band: band,
                                 position: position))
        }

        ranked.sort { a, b in
            if a.match != b.match { return a.match < b.match }
            if a.band != b.band { return a.band < b.band }
            return a.position < b.position
        }
        return ranked
    }

    static func ordered(_ foods: [ResolvedFood], query: String,
                        region: FoodRegion?, ownIDs: Set<String>,
                        recentIDs: Set<String> = []) -> [ResolvedFood] {
        ranked(foods, query: query, region: region, ownIDs: ownIDs,
               recentIDs: recentIDs).map(\.food)
    }
}
