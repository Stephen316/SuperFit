import Foundation
import SwiftData

/// Resolution order: local cache → USDA FoodData Central → Open Food Facts.
/// Anything fetched is cached as a Food row, so previously logged foods still
/// resolve offline even though search itself needs a connection.
/// See docs/API_INTEGRATIONS.md.
@MainActor
final class FoodResolver {
    private let off = OpenFoodFactsClient()
    private let usda: USDAClient
    private let context: ModelContext

    init(context: ModelContext, usda: USDAClient = USDAClient()) {
        self.context = context
        self.usda = usda
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
    func search(_ term: String, page: Int = 1, brand: StoreBrand? = nil) async -> SearchPage {
        let trimmed = term.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 || brand != nil else {
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
        async let usdaResults = filteringByStore
            ? nil : try? usda.search(trimmed, page: page)
        async let offResults = try? off.search(trimmed, page: page, brand: brand)

        let usdaPage = await usdaResults ?? []
        let offPage = await offResults

        var seen = Set(local.map(\.id))
        var out = local
        for f in supplements + usdaPage + (offPage?.foods ?? [])
        where seen.insert(f.id).inserted {
            out.append(f)
        }
        // USDA reports no page count, so a full page implies another may exist.
        let usdaHasMore = usdaPage.count >= USDAClient.pageSize
        return SearchPage(foods: out, hasMore: usdaHasMore || (offPage?.hasMore ?? false))
    }

    /// Fills in USDA household measures, which the search endpoint omits.
    /// Returns the food unchanged when it already has portions, isn't a USDA
    /// item, or the request fails — portion data is a convenience, never a
    /// prerequisite for logging.
    func withPortions(_ food: ResolvedFood) async -> ResolvedFood {
        guard food.portions.isEmpty, food.source == .usda,
              let fdcID = Int(food.id.replacingOccurrences(of: "fdc:", with: "")),
              let detailed = try? await usda.detail(fdcID: fdcID),
              !detailed.portions.isEmpty
        else { return food }

        if let cached = cachedFood(remoteID: food.id) {
            cached.portionsJSON = try? JSONEncoder().encode(detailed.portions)
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
        if let existing = cachedFood(remoteID: resolved.id) { return existing }
        let food = Food(name: resolved.name, source: resolved.source)
        food.remoteID = resolved.id
        food.brand = resolved.brand
        food.kcalPer100g = resolved.per100g.kcal
        food.proteinPer100g = resolved.per100g.proteinG
        food.carbsPer100g = resolved.per100g.carbsG
        food.fatPer100g = resolved.per100g.fatG
        food.fibrePer100g = resolved.per100g.fibreG
        // Without this the cached copy returned by localMatches on the next
        // search would re-log the food with macros only.
        food.microsJSON = resolved.per100g.micros.isEmpty
            ? nil : try? JSONEncoder().encode(resolved.per100g.micros)
        food.portionsJSON = resolved.portions.isEmpty
            ? nil : try? JSONEncoder().encode(resolved.portions)
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
        ResolvedFood(id: remoteID ?? id.uuidString,
                     source: FoodSource(rawValue: sourceRaw) ?? .custom,
                     name: name, brand: brand,
                     per100g: NutrientProfile(kcal: kcalPer100g,
                                              proteinG: proteinPer100g,
                                              carbsG: carbsPer100g,
                                              fatG: fatPer100g,
                                              fibreG: fibrePer100g,
                                              micros: microsJSON
                                                  .flatMap { try? JSONDecoder().decode([String: Double].self, from: $0) } ?? [:]),
                     servingGrams: nil,
                     portions: portionsJSON
                        .flatMap { try? JSONDecoder().decode([FoodPortion].self, from: $0) } ?? [])
    }
}
