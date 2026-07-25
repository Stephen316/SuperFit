import Foundation

/// USDA FoodData Central API — generic whole foods plus USDA's branded set,
/// with full micronutrient data.
///
/// Needs a free key from https://fdc.nal.usda.gov/api-key-signup.html. The key
/// is the user's own and lives in the Keychain, never in the binary: a key
/// compiled into an app ships to every install and is trivially extracted.
struct USDAClient: Sendable {

    /// FDC nutrient ids → the app's micronutrient keys.
    private static let microIDs: [Int: Micronutrient] = [
        1258: .saturatedFat, 2000: .sugar, 1253: .cholesterol,
        1093: .sodium, 1092: .potassium, 1087: .calcium, 1089: .iron,
        1090: .magnesium, 1095: .zinc,
        1162: .vitaminC, 1114: .vitaminD, 1106: .vitaminA,
        1178: .vitaminB12, 1177: .folate,
    ]

    private let session: URLSession

    init(session: URLSession = .nutritionDefault) {
        self.session = session
    }

    var hasKey: Bool { USDAKeyStore.key != nil }

    /// Generic foods first (Foundation and SR Legacy are lab-analyzed), then
    /// USDA's branded entries. Returns [] with no key rather than throwing —
    /// search still works through the local cache and Open Food Facts.
    func search(_ term: String, limit: Int = 25) async throws -> [ResolvedFood] {
        guard let key = USDAKeyStore.key else { return [] }
        let query = String(term.prefix(80)).trimmingCharacters(in: .whitespaces)
        guard query.count >= 2 else { return [] }

        var comps = URLComponents(string: "https://api.nal.usda.gov/fdc/v1/foods/search")!
        comps.queryItems = [
            .init(name: "query", value: query),
            .init(name: "pageSize", value: String(min(limit, 50))),
            .init(name: "dataType", value: "Foundation,SR Legacy,Branded"),
            .init(name: "api_key", value: key),
        ]

        guard let url = comps.url else { throw URLError(.badURL) }
        let response: SearchResponse = try await session.getJSON(url)
        return response.foods.compactMap(\.resolved)
    }

    /// Cheap round trip used by Settings to confirm a pasted key works.
    func validate(key: String) async -> Bool {
        var comps = URLComponents(string: "https://api.nal.usda.gov/fdc/v1/foods/search")!
        comps.queryItems = [
            .init(name: "query", value: "apple"),
            .init(name: "pageSize", value: "1"),
            .init(name: "api_key", value: key),
        ]
        guard let url = comps.url,
              let (_, response) = try? await session.data(from: url),
              let http = response as? HTTPURLResponse else { return false }
        return (200..<300).contains(http.statusCode)
    }

    fileprivate struct SearchResponse: Decodable {
        let foods: [Food]

        struct Food: Decodable {
            let fdcId: Int
            let description: String
            let brandOwner: String?
            let brandName: String?
            let servingSize: Double?
            let servingSizeUnit: String?
            let foodNutrients: [Nutrient]?

            struct Nutrient: Decodable {
                let nutrientId: Int?
                let value: Double?
                // FDC returns either flat (nutrientId/value) or nested
                // (nutrient.id/amount) shapes depending on dataType. Decoding
                // both keeps a shape change from silently zeroing every macro.
                let nutrient: Inner?
                let amount: Double?

                struct Inner: Decodable {
                    let id: Int?
                }

                var id: Int? { nutrientId ?? nutrient?.id }
                var quantity: Double? { value ?? amount }
            }

            var resolved: ResolvedFood? {
                let name = description.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return nil }

                var profile = NutrientProfile()
                var micros: [String: Double] = [:]
                var sawEnergy = false

                for n in foodNutrients ?? [] {
                    guard let id = n.id, let value = n.quantity else { continue }
                    switch id {
                    case 1008: profile.kcal = value; sawEnergy = true
                    case 1003: profile.proteinG = value
                    case 1004: profile.fatG = value
                    case 1005: profile.carbsG = value
                    case 1079: profile.fibreG = value
                    default:
                        if let micro = USDAClient.microIDs[id] { micros[micro.rawValue] = value }
                    }
                }
                guard sawEnergy else { return nil }
                profile.micros = micros

                let brand = (brandName ?? brandOwner)?.trimmingCharacters(in: .whitespaces)
                return ResolvedFood(
                    id: "fdc:\(fdcId)",
                    source: .usda,
                    name: name,
                    brand: (brand?.isEmpty ?? true) ? nil : brand,
                    per100g: profile,
                    servingGrams: servingSizeUnit?.lowercased() == "g" ? servingSize : nil)
            }
        }
    }
}

/// The user's own FDC key. Keychain, not UserDefaults — it is a credential.
enum USDAKeyStore {
    private static let account = "usda.apiKey"

    static var key: String? {
        Keychain.read(account)
    }

    static func save(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        trimmed.isEmpty ? Keychain.delete(account) : Keychain.write(trimmed, account: account)
    }

    static func clear() {
        Keychain.delete(account)
    }
}
