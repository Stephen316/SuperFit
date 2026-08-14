import Foundation
import SwiftData

/// Shared limits for food search, in one place because the guard is repeated in
/// the resolver, both API clients, and the empty-state text — four copies that
/// would otherwise drift apart and let a query reach one source but not another.
enum FoodSearch {
    /// Shortest query that reaches the network.
    ///
    /// Three, not two: a two-letter term almost never means what the user
    /// intended, and one completed search costs 5–7 requests across the two
    /// sources' datasets and country tiers.
    static let minimumQueryLength = 3
}

/// Resolution order: local cache → USDA FoodData Central → Open Food Facts.
/// Anything fetched is cached as a Food row, so previously logged foods still
/// resolve offline even though search itself needs a connection.
/// See docs/API_INTEGRATIONS.md.
@MainActor
final class FoodResolver {
    private let off: OpenFoodFactsClient
    private let usda: USDAClient
    private let cache: FoodSearchCache
    private let context: ModelContext

    /// Both clients are injectable. Only USDA was, which quietly meant any test
    /// of this type reached the live Open Food Facts API — slow, flaky, and
    /// returning whatever happens to be in the database today rather than what
    /// the test set up.
    /// The cache is injectable for the same reason the clients are: sharing one
    /// process-wide instance makes tests order-dependent, where an entry stored by
    /// one leaks into the next and quietly stands in for a request that was
    /// supposed to be made.
    init(context: ModelContext,
         usda: USDAClient = USDAClient(),
         off: OpenFoodFactsClient = OpenFoodFactsClient(),
         cache: FoodSearchCache = .shared) {
        self.context = context
        self.usda = usda
        self.off = off
        self.cache = cache
    }

    func byBarcode(_ barcode: String) async -> ResolvedFood? {
        if let cached = cachedFood(remoteID: barcode) { return cached.resolved }
        guard let remote = try? await off.product(barcode: barcode) else { return nil }
        cache(remote)
        return remote
    }

    /// One page of merged results, and whether asking for another is worthwhile.
    struct SearchPage: Sendable {
        var foods: [ResolvedFood]
        var hasMore: Bool
    }

    /// Cache and supplements first so results appear instantly and offline; the
    /// two networks run concurrently and either failing leaves the others intact.
    ///
    /// Local rows and supplements are page-1 only: they're already complete, and
    /// repeating them on every page would push the remote results the user is
    /// paging *for* further down each time.
    func search(_ term: String, page: Int = 1, brand: StoreBrand? = nil,
                region: FoodRegion? = nil) async -> SearchPage {
        let trimmed = term.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= FoodSearch.minimumQueryLength || brand != nil else {
            return SearchPage(foods: [], hasMore: false)
        }

        let firstPage = page <= 1
        // A store filter is asking for that retailer's own brand specifically, so
        // cached rows, supplements and USDA generics are all off-topic. USDA has
        // no supermarket own-brand ranges outside the US and no tag to filter on
        // regardless, so querying it would only dilute the results.
        let filteringByStore = brand != nil
        let local = firstPage && !filteringByStore ? localMatches(trimmed) : []
        // Protein bars, shakes and gainers are snacks and meals as much as
        // supplements — someone reaching for "protein bar" in the food diary
        // should find it there, not only in the supplements list.
        let supplements = firstPage && !filteringByStore ? supplementMatches(trimmed) : []
        // USDA's branded set is US-only, so it's the local shelf for a US user
        // and the bottom provenance band for everyone else. Fetched accordingly
        // rather than always: see USDAClient.search.
        let usdaWantsBranded = region?.code == "US"
        async let usdaResults = filteringByStore
            ? nil : try? usda.search(trimmed, page: page,
                                     includeBranded: usdaWantsBranded)
        async let offResults = try? off.search(trimmed, page: page, region: region,
                                              brand: brand)

        let usdaPage = await usdaResults ?? []
        let offPage = await offResults

        var seen = Set(local.map(\.id))
        var out = local
        for f in supplements + usdaPage + (offPage?.foods ?? [])
        where seen.insert(f.id).inserted {
            out.append(f)
        }

        // Rank by what the food *is* and where it's sold, not by which API
        // returned it. Concatenating source by source put up to 50 USDA entries —
        // mostly US branded — above every Tesco product for a UK user, and
        // provenance alone still can't tell rice from rice cakes.
        out = FoodRelevance.ordered(out, query: trimmed, region: region,
                                    ownIDs: Set(local.map(\.id)),
                                    recentIDs: recentlyEatenIDs())

        // USDA reports no page count, so a full page implies another may exist.
        // Measured against the generic page, which is the widest of the requests.
        let usdaHasMore = usdaPage.count >= USDAClient.genericPageSize
        return SearchPage(foods: out, hasMore: usdaHasMore || (offPage?.hasMore ?? false))
    }

    /// The same search, delivered in pieces as each source answers.
    ///
    /// Awaiting everything made every search as slow as the slowest source.
    /// Measured on one term: Open Food Facts answered in **0.18s** with 8.7 KB,
    /// USDA's generics took **2.0s** and 1.6 MB, and the survey set another
    /// **1.8s** per attempt with up to three attempts. So a list that could have
    /// appeared in a fifth of a second waited two seconds, sometimes five.
    ///
    /// Each yield is the complete ranked list so far, not a delta, so the caller
    /// assigns rather than merges and the ordering stays correct at every step.
    func stream(_ term: String, page: Int = 1, brand: StoreBrand? = nil,
                region: FoodRegion? = nil) -> AsyncStream<SearchPage> {
        AsyncStream { continuation in
            let work = Task { @MainActor in
                let trimmed = term.trimmingCharacters(in: .whitespaces)
                guard trimmed.count >= FoodSearch.minimumQueryLength || brand != nil else {
                    continuation.yield(SearchPage(foods: [], hasMore: false))
                    return continuation.finish()
                }

                let firstPage = page <= 1
                let filteringByStore = brand != nil
                let local = firstPage && !filteringByStore ? localMatches(trimmed) : []
                let supplements = firstPage && !filteringByStore
                    ? supplementMatches(trimmed) : []
                let ownIDs = Set(local.map(\.id))
                // Computed once per search, not per yield: it hits the store and
                // the answer can't change while one search is in flight.
                let recentIDs = self.recentlyEatenIDs()

                // What's already on the device costs nothing, so it goes up
                // immediately rather than behind a spinner waiting on a network.
                var collected = local + supplements
                var seen = Set(collected.map(\.id))
                var hasMore = false
                func publish() {
                    continuation.yield(SearchPage(
                        foods: FoodRelevance.ordered(collected, query: trimmed,
                                                     region: region, ownIDs: ownIDs,
                                                     recentIDs: recentIDs),
                        hasMore: hasMore))
                }
                if !collected.isEmpty { publish() }

                let usda = self.usda
                let off = self.off
                let wantsBranded = region?.code == "US"

                let cache = self.cache
                func key(_ leg: String) -> FoodSearchCache.Key {
                    .init(leg: leg, query: trimmed, page: page,
                          region: region, brand: brand)
                }

                // A cached leg is applied before anything is dispatched, so a
                // repeated search paints from memory with no request at all.
                var legsToFetch: [String] = ["off"]
                if !filteringByStore { legsToFetch += ["usda-core", "usda-survey"] }
                var pending: [String] = []
                for leg in legsToFetch {
                    guard let hit = cache.value(for: key(leg)) else {
                        pending.append(leg)
                        continue
                    }
                    for food in hit.foods where seen.insert(food.id).inserted {
                        collected.append(food)
                    }
                    hasMore = hasMore || hit.hasMore
                }
                if !collected.isEmpty { publish() }
                if pending.isEmpty { return continuation.finish() }

                // Whatever wasn't cached, each publishing on arrival. Open Food
                // Facts nearly always wins by an order of magnitude, which is the
                // whole point.
                await withTaskGroup(of: (leg: String, foods: [ResolvedFood], more: Bool).self) { group in
                    if pending.contains("off") {
                        group.addTask {
                            let page = try? await off.search(trimmed, page: page,
                                                             region: region, brand: brand)
                            return ("off", page?.foods ?? [], page?.hasMore ?? false)
                        }
                    }
                    if pending.contains("usda-core") {
                        group.addTask {
                            let foods = (try? await usda.searchCore(
                                trimmed, page: page, includeBranded: wantsBranded)) ?? []
                            return ("usda-core", foods,
                                    foods.count >= USDAClient.genericPageSize)
                        }
                    }
                    if pending.contains("usda-survey") {
                        group.addTask {
                            ("usda-survey", await usda.searchSurvey(trimmed, page: page), false)
                        }
                    }

                    for await leg in group {
                        if Task.isCancelled { break }
                        cache.store(leg.foods, hasMore: leg.more, for: key(leg.leg))
                        var added = false
                        for food in leg.foods where seen.insert(food.id).inserted {
                            collected.append(food)
                            added = true
                        }
                        hasMore = hasMore || leg.more
                        if added || leg.more { publish() }
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in work.cancel() }
        }
    }

    /// Fills in USDA household measures, which the search endpoint omits.
    /// Returns the food unchanged when it already has portions, isn't a USDA
    /// item, or the request fails — portion data is a convenience, never a
    /// prerequisite for logging.
    func withPortions(_ food: ResolvedFood) async -> ResolvedFood {
        guard food.portions.isEmpty, food.source == .usda,
              let fdcID = Int(food.id.replacingOccurrences(of: "fdc:", with: "")),
              let detailed = try? await usda.detail(fdcID: fdcID),
              !detailed.portions.isEmpty || detailed.effectiveGramsPerMillilitre != nil
        else { return food }

        if let cached = cachedFood(remoteID: food.id) {
            cached.portionsJSON = try? JSONEncoder().encode(detailed.portions)
            cached.waterGPer100g = detailed.per100g.waterG
            cached.gramsPerMillilitre = detailed.effectiveGramsPerMillilitre
            try? context.save()
        }
        return detailed
    }

    /// The stored row behind a search result, if there is one.
    ///
    /// Remote hits that have never been logged have no local row — nothing to
    /// delete, and the UI shouldn't offer to.
    func storedFood(for resolved: ResolvedFood) -> Food? {
        if let cached = cachedFood(remoteID: resolved.id) { return cached }
        guard let uuid = UUID(uuidString: resolved.id) else { return nil }
        var d = FetchDescriptor<Food>(predicate: #Predicate { $0.id == uuid })
        d.fetchLimit = 1
        return try? context.fetch(d).first
    }

    /// Removes a food from the local list.
    ///
    /// Logged entries are untouched: `NutritionLog` snapshots macros at log
    /// time, so deleting the food it came from cannot rewrite history. Saved
    /// meals referencing it will report a missing ingredient rather than
    /// silently under-counting — see `MealComposer`.
    @discardableResult
    func delete(_ resolved: ResolvedFood) -> Bool {
        guard let food = storedFood(for: resolved) else { return false }
        context.delete(food)
        try? context.save()
        return true
    }

    /// Persist a remote result locally (dedupes by remoteID).
    @discardableResult
    func cache(_ resolved: ResolvedFood) -> Food {
        if let existing = cachedFood(remoteID: resolved.id) {
            // A previous build may have cached macros before water and liquid
            // measures were supported. Enrich it from the fresh result instead
            // of permanently returning the incomplete local copy.
            if let water = resolved.per100g.waterG { existing.waterGPer100g = water }
            if let density = resolved.effectiveGramsPerMillilitre {
                existing.gramsPerMillilitre = density
            }
            if !resolved.portions.isEmpty {
                existing.portionsJSON = try? JSONEncoder().encode(resolved.portions)
            }
            // Same reasoning for allergens: anything cached before this feature
            // existed holds none, and would otherwise never gain them.
            if !resolved.allergenTags.isEmpty {
                existing.allergenTagsRaw = resolved.allergenTags.joined(separator: ",")
            }
            if !resolved.traceTags.isEmpty {
                existing.traceTagsRaw = resolved.traceTags.joined(separator: ",")
            }
            if let ingredients = resolved.ingredientsText {
                existing.ingredientsText = ingredients
            }
            try? context.save()
            return existing
        }
        let food = Food(name: resolved.name, source: resolved.source)
        food.remoteID = resolved.id
        food.brand = resolved.brand
        food.kcalPer100g = resolved.per100g.kcal
        food.proteinPer100g = resolved.per100g.proteinG
        food.carbsPer100g = resolved.per100g.carbsG
        food.fatPer100g = resolved.per100g.fatG
        food.fibrePer100g = resolved.per100g.fibreG
        food.waterGPer100g = resolved.per100g.waterG
        food.gramsPerMillilitre = resolved.effectiveGramsPerMillilitre
        // Without this the cached copy returned by localMatches on the next
        // search would re-log the food with macros only.
        food.microsJSON = resolved.per100g.micros.isEmpty
            ? nil : try? JSONEncoder().encode(resolved.per100g.micros)
        food.portionsJSON = resolved.portions.isEmpty
            ? nil : try? JSONEncoder().encode(resolved.portions)
        food.allergenTagsRaw = resolved.allergenTags.joined(separator: ",")
        food.traceTagsRaw = resolved.traceTags.joined(separator: ",")
        food.ingredientsText = resolved.ingredientsText
        context.insert(food)
        try? context.save()
        return food
    }

    // MARK: - Local

    private func cachedFood(remoteID: String) -> Food? {
        var d = FetchDescriptor<Food>(predicate: #Predicate { $0.remoteID == remoteID })
        d.fetchLimit = 1
        return try? context.fetch(d).first
    }

    private func supplementMatches(_ term: String) -> [ResolvedFood] {
        let d = FetchDescriptor<Supplement>(
            predicate: #Predicate { $0.name.localizedStandardContains(term) })
        return ((try? context.fetch(d)) ?? [])
            .compactMap(\.asFood)
            .sorted { $0.name.count < $1.name.count }
    }

    /// Ids of everything eaten in the last few days, in both the forms a
    /// `ResolvedFood` can carry: a cached remote item is keyed by its source id
    /// ("fdc:171077", a barcode), a hand-made one by its UUID.
    ///
    /// Read per search rather than cached — five days is a moving window and a
    /// food logged a minute ago should lead the next search, not the one after.
    private func recentlyEatenIDs() -> Set<String> {
        let cutoff = Calendar.current.date(byAdding: .day,
                                           value: -FoodRelevance.recentDays,
                                           to: .now) ?? .now
        let logs = FetchDescriptor<NutritionLog>(
            predicate: #Predicate { $0.date >= cutoff })
        let eaten = Set(((try? context.fetch(logs)) ?? []).compactMap(\.foodID))
        guard !eaten.isEmpty else { return [] }

        let foods = FetchDescriptor<Food>(
            predicate: #Predicate { eaten.contains($0.id) })
        var out = Set<String>()
        for food in (try? context.fetch(foods)) ?? [] {
            out.insert(food.id.uuidString)
            if let remote = food.remoteID { out.insert(remote) }
        }
        return out
    }

    private func localMatches(_ term: String) -> [ResolvedFood] {
        let d = FetchDescriptor<Food>(
            predicate: #Predicate { $0.name.localizedStandardContains(term) })
        return ((try? context.fetch(d)) ?? [])
            .sorted {
                if $0.isFavorite != $1.isFavorite { return $0.isFavorite }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            .prefix(25)
            .map(\.resolved)
    }
}

extension Supplement {
    /// The same product expressed as a food. Supplement figures are per serving
    /// while foods are per 100 g, so they're rescaled — and `servingGrams` is
    /// carried through so "use 1 serving" still means one scoop or one bar.
    var asFood: ResolvedFood? {
        guard isFoodLike, let grams = servingGrams, grams > 0 else { return nil }
        let factor = 100 / grams
        let s = perServing
        return ResolvedFood(
            id: "supplement:\(id.uuidString)",
            source: .supplement,
            name: name,
            brand: "Supplement",
            per100g: NutrientProfile(kcal: s.kcal * factor,
                                     proteinG: s.proteinG * factor,
                                     carbsG: s.carbsG * factor,
                                     fatG: s.fatG * factor,
                                     fibreG: s.fibreG * factor,
                                     micros: s.micros.mapValues { $0 * factor }),
            servingGrams: grams,
            // The label already names the measure — "30 g scoop", "60 g bar" —
            // so it makes a better portion than a generic "1 serving".
            portions: [FoodPortion(label: "1 \(servingLabel)", gramWeight: grams)])
    }
}

extension Food {
    var resolved: ResolvedFood {
        var food = resolvedCore
        // Without these the cached copy a second search returns would lose its
        // allergen tags, and a food already seen would stop showing as safe.
        food.allergenTags = allergenTagsRaw.split(separator: ",").map(String.init)
        food.traceTags = traceTagsRaw.split(separator: ",").map(String.init)
        food.ingredientsText = ingredientsText
        return food
    }

    private var resolvedCore: ResolvedFood {
        ResolvedFood(id: remoteID ?? id.uuidString,
                     source: FoodSource(rawValue: sourceRaw) ?? .custom,
                     name: name, brand: brand,
                     per100g: NutrientProfile(kcal: kcalPer100g,
                                              proteinG: proteinPer100g,
                                              carbsG: carbsPer100g,
                                              fatG: fatPer100g,
                                              fibreG: fibrePer100g,
                                              waterG: waterGPer100g,
                                              micros: microsJSON
                                                  .flatMap { try? JSONDecoder().decode([String: Double].self, from: $0) } ?? [:]),
                     servingGrams: nil,
                     portions: portionsJSON
                        .flatMap { try? JSONDecoder().decode([FoodPortion].self, from: $0) } ?? [],
                     gramsPerMillilitre: gramsPerMillilitre)
    }
}
