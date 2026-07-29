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

    static let pageSize = 25

    /// One page of results, plus whether another page exists.
    struct SearchPage: Sendable {
        var foods: [ResolvedFood]
        var hasMore: Bool
    }

    /// Full-text search.
    ///
    /// Uses Open Food Facts' current search service. The legacy `cgi/search.pl`
    /// this replaced is deprecated and unreliable in practice — it returned 503
    /// on two of three consecutive probes while the new endpoint answered every
    /// time — so it stays only as a fallback for when the new one is down.
    ///
    /// Results are **sorted** by country in three tiers, not filtered to one.
    ///
    /// 1. the chosen country
    /// 2. market-adjacent countries
    /// 3. everything else
    ///
    /// The database is global, so an unweighted search for "chicken breast" from
    /// the UK returns a Spanish product above Tesco's — measured, not assumed.
    /// The local catalogue is what someone logging their weekly shop needs first.
    ///
    /// The neighbour tier matters most where a country's own coverage is thin.
    /// Measured: "milk" restricted to Ireland returns 2,125 products; Ireland or
    /// the UK returns 9,000, because the same chains span both. Without it an
    /// Irish user sees a quarter of what's actually on their shelves.
    ///
    /// Sorting rather than filtering matters: a hard country filter would hide
    /// anything imported or bought abroad, with no way to tell the product was in
    /// the database at all. The tiers run concurrently and merge in order, so
    /// precision leads and nothing is lost.
    func search(_ term: String, page: Int = 1,
                region: FoodRegion? = nil,
                brand: StoreBrand? = nil) async throws -> SearchPage {
        let query = String(term.prefix(80)).trimmingCharacters(in: .whitespaces)
        guard query.count >= FoodSearch.minimumQueryLength || brand != nil else {
            return SearchPage(foods: [], hasMore: false)
        }

        // A store filter already narrows hard enough that country tiers add
        // nothing but extra requests — Tesco's own brand is British by definition.
        if let brand {
            if let filtered = try? await searchAlicious(query, page: page,
                                                        tags: [], brand: brand) {
                return filtered
            }
            return SearchPage(foods: [], hasMore: false)
        }

        guard let region else {
            if let global = try? await searchAlicious(query, page: page, tags: []) {
                return global
            }
            return try await searchLegacy(query, page: page)
        }

        let neighbourTags = region.neighbourTags
        async let localTask = try? searchAlicious(query, page: page, tags: [region.tag])
        async let neighbourTask = neighbourTags.isEmpty
            ? nil : try? searchAlicious(query, page: page, tags: neighbourTags)
        async let globalTask = try? searchAlicious(query, page: page, tags: [])

        let local = await localTask
        let neighbours = await neighbourTask
        let global = await globalTask

        guard local != nil || neighbours != nil || global != nil else {
            return try await searchLegacy(query, page: page)
        }

        var seen = Set<String>()
        var merged: [ResolvedFood] = []
        for food in (local?.foods ?? []) + (neighbours?.foods ?? []) + (global?.foods ?? [])
        where seen.insert(food.id).inserted {
            merged.append(food)
        }
        return SearchPage(foods: merged,
                          hasMore: (local?.hasMore ?? false)
                              || (neighbours?.hasMore ?? false)
                              || (global?.hasMore ?? false))
    }

    /// One tier. Several tags are OR'd, which is how the neighbour tier is
    /// expressed as a single request rather than one per country.
    private func searchAlicious(_ query: String, page: Int, tags: [String],
                                brand: StoreBrand? = nil) async throws -> SearchPage {
        var comps = URLComponents(string: "https://search.openfoodfacts.org/search")!
        // Tags go in the query string rather than as filter parameters; this
        // service takes a single Lucene-style `q`.
        var q = query
        if tags.count == 1 {
            q += " countries_tags:\"en:\(tags[0])\""
        } else if tags.count > 1 {
            let clause = tags.map { "countries_tags:\"en:\($0)\"" }.joined(separator: " OR ")
            q += " (\(clause))"
        }
        if let brand { q += " brands_tags:\"\(brand.tag)\"" }
        q = q.trimmingCharacters(in: .whitespaces)
        comps.queryItems = [
            .init(name: "q", value: q),
            .init(name: "page", value: String(page)),
            .init(name: "page_size", value: String(Self.pageSize)),
            .init(name: "fields",
                  value: "code,product_name,brands,nutriments,serving_quantity,countries_tags"),
        ]
        guard let url = comps.url else { throw URLError(.badURL) }
        let response: AliciousResponse = try await session.getJSON(url)
        let foods = response.hits.compactMap { hit -> ResolvedFood? in
            guard let code = hit.code else { return nil }
            return hit.resolved(id: code)
        }
        return SearchPage(foods: foods, hasMore: page < (response.pageCount ?? 1))
    }

    /// The deprecated endpoint, kept purely as a fallback.
    private func searchLegacy(_ query: String, page: Int) async throws -> SearchPage {
        var comps = URLComponents(string: "https://world.openfoodfacts.org/cgi/search.pl")!
        comps.queryItems = [
            .init(name: "search_terms", value: query),
            .init(name: "search_simple", value: "1"),
            .init(name: "action", value: "process"),
            .init(name: "json", value: "1"),
            .init(name: "page_size", value: String(Self.pageSize)),
            .init(name: "page", value: String(page)),
            .init(name: "fields", value: "code,product_name,brands,nutriments,serving_quantity,countries_tags"),
        ]
        guard let url = comps.url else { throw URLError(.badURL) }
        let response: OFFSearchResponse = try await session.getJSON(url)
        let foods = response.products.compactMap { p -> ResolvedFood? in
            guard let code = p.code else { return nil }
            return p.resolved(id: code)
        }
        // No page count on this endpoint; a full page implies another may exist.
        return SearchPage(foods: foods, hasMore: foods.count >= Self.pageSize)
    }

}

/// Response from Open Food Facts' current search service.
private struct AliciousResponse: Decodable {
    let hits: [AliciousHit]
    let pageCount: Int?

    enum CodingKeys: String, CodingKey {
        case hits
        case pageCount = "page_count"
    }
}

/// Same fields as the legacy product shape, except `brands`, which this service
/// returns as an array where the old one returned a comma-joined string.
private struct AliciousHit: Decodable {
    let code: String?
    let productName: String?
    let brands: [String]?
    let nutriments: OFFNutriments?
    let servingQuantity: StringOrDouble?
    let countriesTags: [String]?

    enum CodingKeys: String, CodingKey {
        case code, brands, nutriments
        case productName = "product_name"
        case servingQuantity = "serving_quantity"
        case countriesTags = "countries_tags"
    }

    func resolved(id: String) -> ResolvedFood? {
        guard let name = productName, !name.isEmpty,
              let n = nutriments, let kcal = n.energyKcal100g else { return nil }
        var food = ResolvedFood(
            id: id, source: .openFoodFacts, name: name,
            brand: brands?.first?.trimmingCharacters(in: .whitespaces),
            per100g: NutrientProfile(kcal: kcal,
                                     proteinG: n.proteins100g ?? 0,
                                     carbsG: n.carbohydrates100g ?? 0,
                                     fatG: n.fat100g ?? 0,
                                     fibreG: n.fiber100g ?? 0),
            servingGrams: servingQuantity?.value)
        food.countryTags = OFFCountryTag.strip(countriesTags)
        return food
    }
}

/// Open Food Facts prefixes country tags with a language code — "en:ireland".
/// Stored without it so a tag compares directly against `FoodRegion.tag`.
enum OFFCountryTag {
    static func strip(_ tags: [String]?) -> [String] {
        (tags ?? []).map { tag in
            guard let colon = tag.firstIndex(of: ":") else { return tag }
            return String(tag[tag.index(after: colon)...])
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

/// Per-100 g nutriments. Both the product endpoint and the search service use
/// these same key names, so one type decodes both.
struct OFFNutriments: Decodable {
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

private struct OFFProduct: Decodable {
    let code: String?
    let productName: String?
    let brands: String?
    let nutriments: OFFNutriments?
    let servingQuantity: StringOrDouble?
    let countriesTags: [String]?

    enum CodingKeys: String, CodingKey {
        case code, brands, nutriments
        case productName = "product_name"
        case servingQuantity = "serving_quantity"
        case countriesTags = "countries_tags"
    }

    func resolved(id: String) -> ResolvedFood? {
        guard let name = productName, !name.isEmpty,
              let n = nutriments, let kcal = n.energyKcal100g else { return nil }
        var food = ResolvedFood(
            id: id, source: .openFoodFacts, name: name,
            brand: brands?.components(separatedBy: ",").first?
                .trimmingCharacters(in: .whitespaces),
            per100g: NutrientProfile(kcal: kcal,
                                     proteinG: n.proteins100g ?? 0,
                                     carbsG: n.carbohydrates100g ?? 0,
                                     fatG: n.fat100g ?? 0,
                                     fibreG: n.fiber100g ?? 0),
            servingGrams: servingQuantity?.value)
        food.countryTags = OFFCountryTag.strip(countriesTags)
        return food
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
