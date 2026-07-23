import Foundation

/// Open Food Facts — crowd-sourced, barcode-first, no API key.
/// Missing nutriments stay nil upstream; never coerced to zero here.
struct OpenFoodFactsClient: Sendable {
    private let session: URLSession

    init(session: URLSession = .nutritionDefault) {
        self.session = session
    }

    func product(barcode: String) async throws -> ResolvedFood? {
        let code = barcode.filter(\.isNumber).prefix(14)
        guard code.count >= 8 else { return nil }
        let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(code).json")!
        let response: OFFProductResponse = try await session.getJSON(url)
        guard response.status == 1, let p = response.product else { return nil }
        return p.resolved(id: String(code))
    }

    func search(_ term: String, page: Int = 1) async throws -> [ResolvedFood] {
        let query = String(term.prefix(80))
        var comps = URLComponents(string: "https://world.openfoodfacts.org/cgi/search.pl")!
        comps.queryItems = [
            .init(name: "search_terms", value: query),
            .init(name: "search_simple", value: "1"),
            .init(name: "action", value: "process"),
            .init(name: "json", value: "1"),
            .init(name: "page_size", value: "25"),
            .init(name: "page", value: String(page)),
            .init(name: "fields", value: "code,product_name,brands,nutriments,serving_quantity"),
        ]
        let response: OFFSearchResponse = try await session.getJSON(comps.url!)
        return response.products.compactMap { p in
            guard let code = p.code else { return nil }
            return p.resolved(id: code)
        }
    }
}

private struct OFFProductResponse: Decodable {
    let status: Int
    let product: OFFProduct?
}

private struct OFFSearchResponse: Decodable {
    let products: [OFFProduct]
}

private struct OFFProduct: Decodable {
    let code: String?
    let productName: String?
    let brands: String?
    let nutriments: Nutriments?
    let servingQuantity: StringOrDouble?

    enum CodingKeys: String, CodingKey {
        case code, brands, nutriments
        case productName = "product_name"
        case servingQuantity = "serving_quantity"
    }

    struct Nutriments: Decodable {
        let energyKcal100g: Double?
        let proteins100g: Double?
        let carbohydrates100g: Double?
        let fat100g: Double?
        let fiber100g: Double?

        enum CodingKeys: String, CodingKey {
            case energyKcal100g = "energy-kcal_100g"
            case proteins100g = "proteins_100g"
            case carbohydrates100g = "carbohydrates_100g"
            case fat100g = "fat_100g"
            case fiber100g = "fiber_100g"
        }
    }

    func resolved(id: String) -> ResolvedFood? {
        guard let name = productName, !name.isEmpty,
              let n = nutriments, let kcal = n.energyKcal100g else { return nil }
        return ResolvedFood(
            id: id, source: .openFoodFacts, name: name,
            brand: brands?.components(separatedBy: ",").first?
                .trimmingCharacters(in: .whitespaces),
            per100g: NutrientProfile(kcal: kcal,
                                     proteinG: n.proteins100g ?? 0,
                                     carbsG: n.carbohydrates100g ?? 0,
                                     fatG: n.fat100g ?? 0,
                                     fibreG: n.fiber100g ?? 0),
            servingGrams: servingQuantity?.value)
    }
}

/// OFF returns serving_quantity as either a string or a number.
struct StringOrDouble: Decodable {
    let value: Double?
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        value = (try? c.decode(Double.self)) ?? Double((try? c.decode(String.self)) ?? "")
    }
}

extension URLSession {
    static let nutritionDefault: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 20
        config.httpAdditionalHeaders = ["User-Agent": "SuperFit/1.0 (iOS)"]
        config.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(configuration: config)
    }()

    func getJSON<T: Decodable>(_ url: URL) async throws -> T {
        let (data, response) = try await data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        guard data.count < 5_000_000 else { throw URLError(.dataLengthExceedsMaximum) }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
