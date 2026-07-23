import Foundation

/// Bundled USDA FoodData Central generic foods (Foundation + SR Legacy,
/// public domain, built by tools/build_fdc_seed.py). ~7,800 lab-analyzed whole
/// foods searched in memory — offline, no API key. Items only become Food rows
/// when the user logs them, so the seed never bloats the synced store.
struct FDCSeedCatalog: Sendable {

    struct Entry: Decodable {
        let i: Int
        let n: String
        let k: Double
        let p: Double?
        let c: Double?
        let f: Double?
        let b: Double?
    }

    private let entries: [Entry]

    static let shared = FDCSeedCatalog(
        data: Bundle.main.url(forResource: "fdc_seed", withExtension: "json")
            .flatMap { try? Data(contentsOf: $0) } ?? Data())

    init(data: Data) {
        entries = (try? JSONDecoder().decode([Entry].self, from: data)) ?? []
    }

    var count: Int { entries.count }

    /// Token-AND search: every word must appear somewhere in the name, so
    /// "chicken breast" matches FDC's comma-style "Chicken breast, roll, …".
    /// Names starting with the first token rank first, then shorter (more
    /// generic) names.
    func search(_ term: String, limit: Int = 25) -> [ResolvedFood] {
        let tokens = term.lowercased().split(separator: " ").map(String.init)
        guard let first = tokens.first, term.trimmingCharacters(in: .whitespaces).count >= 2
        else { return [] }
        return entries
            .filter { e in
                let name = e.n.lowercased()
                return tokens.allSatisfy(name.contains)
            }
            .sorted {
                let aPrefix = $0.n.lowercased().hasPrefix(first)
                let bPrefix = $1.n.lowercased().hasPrefix(first)
                if aPrefix != bPrefix { return aPrefix }
                return $0.n.count < $1.n.count
            }
            .prefix(limit)
            .map(\.resolved)
    }
}

private extension FDCSeedCatalog.Entry {
    var resolved: ResolvedFood {
        ResolvedFood(id: "fdc:\(i)", source: .usda, name: n, brand: nil,
                     per100g: NutrientProfile(kcal: k, proteinG: p ?? 0,
                                              carbsG: c ?? 0, fatG: f ?? 0,
                                              fibreG: b ?? 0),
                     servingGrams: nil)
    }
}
