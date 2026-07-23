import Foundation
import SwiftData

/// Resolution order: local cache → bundled FDC catalog (generic whole foods,
/// offline, keyless) → Open Food Facts (branded/barcode). Remote fetches are
/// cached as Food rows so repeat logging works offline. See docs/API_INTEGRATIONS.md.
@MainActor
final class FoodResolver {
    private let off = OpenFoodFactsClient()
    private let seed: FDCSeedCatalog
    private let context: ModelContext

    init(context: ModelContext, seed: FDCSeedCatalog = .shared) {
        self.context = context
        self.seed = seed
    }

    func byBarcode(_ barcode: String) async -> ResolvedFood? {
        if let cached = cachedFood(remoteID: barcode) { return cached.resolved }
        guard let remote = try? await off.product(barcode: barcode) else { return nil }
        cache(remote)
        return remote
    }

    func search(_ term: String) async -> [ResolvedFood] {
        let trimmed = term.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else { return [] }

        let local = localMatches(trimmed)
        let generic = seed.search(trimmed)
        let branded = (try? await off.search(trimmed)) ?? []

        var seen = Set(local.map(\.id))
        var out = local
        for f in generic + branded where seen.insert(f.id).inserted {
            out.append(f)
        }
        return out
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
        var d = FetchDescriptor<Food>(
            predicate: #Predicate { $0.name.localizedStandardContains(term) },
            sortBy: [SortDescriptor(\.isFavorite, order: .reverse)])
        d.fetchLimit = 25
        return ((try? context.fetch(d)) ?? []).map(\.resolved)
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
                                              fibreG: fibrePer100g),
                     servingGrams: nil)
    }
}
