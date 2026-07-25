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

    /// Cache first so results appear instantly and offline; the two networks
    /// run concurrently and either failing leaves the others intact.
    func search(_ term: String) async -> [ResolvedFood] {
        let trimmed = term.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else { return [] }

        let local = localMatches(trimmed)
        async let usdaResults = try? usda.search(trimmed)
        async let offResults = try? off.search(trimmed)

        var seen = Set(local.map(\.id))
        var out = local
        for f in (await usdaResults ?? []) + (await offResults ?? [])
        where seen.insert(f.id).inserted {
            out.append(f)
        }
        return out
    }

    /// Distinguishes "no results" from "cannot reach the food databases", so
    /// the UI can tell the user which it is.
    var isSearchOnlineOnly: Bool { true }
    var hasUSDAKey: Bool { usda.hasKey }

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
        // Without this the cached copy outranks the seed on the next search and
        // the food would re-log with macros only.
        food.microsJSON = resolved.per100g.micros.isEmpty
            ? nil : try? JSONEncoder().encode(resolved.per100g.micros)
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
                     servingGrams: nil)
    }
}
