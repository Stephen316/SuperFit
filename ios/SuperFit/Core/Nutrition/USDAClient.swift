import Foundation

/// USDA FoodData Central — authoritative generic/whole foods. Requires a free
/// API key, injected via Secrets.xcconfig → Info.plist (never committed).
struct USDAClient: Sendable {
    private let session: URLSession
    private let apiKey: String?

    init(session: URLSession = .nutritionDefault,
         apiKey: String? = Bundle.main.object(forInfoDictionaryKey: "USDA_API_KEY") as? String) {
        self.session = session
        self.apiKey = apiKey?.isEmpty == false ? apiKey : nil
    }

    var isConfigured: Bool { apiKey != nil }

    func search(_ term: String, page: Int = 1) async throws -> [ResolvedFood] {
        guard let apiKey else { return [] }
        let query = String(term.prefix(80))
        var comps = URLComponents(string: "https://api.nal.usda.gov/fdc/v1/foods/search")!
        comps.queryItems = [
            .init(name: "query", value: query),
            .init(name: "dataType", value: "Foundation,SR Legacy"),
            .init(name: "pageSize", value: "25"),
            .init(name: "pageNumber", value: String(page)),
            .init(name: "api_key", value: apiKey),
        ]
        let response: FDCSearchResponse = try await session.getJSON(comps.url!)
        return response.foods.compactMap { $0.resolved() }
    }
}

private struct FDCSearchResponse: Decodable {
    let foods: [FDCFood]
}

private struct FDCFood: Decodable {
    let fdcId: Int
    let description: String
    let brandOwner: String?
    let foodNutrients: [FDCNutrient]

    struct FDCNutrient: Decodable {
        let nutrientNumber: String?
        let value: Double?
    }

    // FDC nutrient numbers: 208 energy kcal, 203 protein, 204 fat,
    // 205 carbohydrate, 291 fibre. Search-endpoint values are per 100 g.
    func resolved() -> ResolvedFood? {
        var byNumber: [String: Double] = [:]
        for n in foodNutrients {
            if let num = n.nutrientNumber, let v = n.value { byNumber[num] = v }
        }
        guard let kcal = byNumber["208"] else { return nil }
        return ResolvedFood(
            id: "fdc:\(fdcId)", source: .usda,
            name: description.capitalized, brand: brandOwner,
            per100g: NutrientProfile(kcal: kcal,
                                     proteinG: byNumber["203"] ?? 0,
                                     carbsG: byNumber["205"] ?? 0,
                                     fatG: byNumber["204"] ?? 0,
                                     fibreG: byNumber["291"] ?? 0),
            servingGrams: nil)
    }
}
