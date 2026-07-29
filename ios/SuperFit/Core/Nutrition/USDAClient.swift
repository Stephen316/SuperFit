import Foundation

/// USDA FoodData Central API — generic whole foods plus USDA's branded set,
/// with full micronutrient data.
///
/// Needs a free key from https://fdc.nal.usda.gov/api-key-signup.html. The key is
/// the user's own: normally entered in Settings and held in the Keychain, and
/// optionally injected at build time from the gitignored `Secrets.xcconfig` for a
/// personal build, since Keychain entries don't survive a reinstall without
/// iCloud Keychain. See `USDAKeyStore` for why that trade is acceptable here and
/// not for a build given to anyone else.
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
    /// Injected so "no key configured at all" stays testable. Under the test
    /// runner `Bundle.main` is the host app, which carries the build-time key,
    /// so clearing the Keychain alone no longer produces a key-less client.
    private let resolveKey: @Sendable () -> String?

    init(session: URLSession = .nutritionDefault,
         key: @escaping @Sendable () -> String? = { USDAKeyStore.key }) {
        self.session = session
        self.resolveKey = key
    }

    var hasKey: Bool { resolveKey() != nil }

    static let pageSize = 25

    /// The lab-analysed whole foods, asked for on their own rather than mixed in
    /// with the branded set.
    ///
    /// Mixed, they lose. Measured over six terms at the old 25-result window,
    /// "milk", "chocolate" and "yoghurt" returned **no** generic entries at all —
    /// branded products filled every slot — so no amount of reordering could
    /// surface plain milk, because plain milk was never in the response.
    private static let genericSearchDataTypes = "Foundation,SR Legacy"

    private static let brandedDataType = "Branded"

    /// Asked for wide, because USDA's own ordering is close to useless and the
    /// real food sits deep in the list. Measured, searching the generic sets:
    /// "rice" put actual rice at #39 behind rice crackers and rice cakes, "oats"
    /// put rolled oats at #18 behind oat bran bagels and "Oil, oat".
    ///
    /// Fifty covers every term measured while `FoodNameMatch` pulls the real food
    /// to the top. It isn't larger because USDA sends roughly 29 KB per result and
    /// offers no way to ask for less — no field selection, and `format=abridged`
    /// is ignored by this endpoint — so the page size *is* the data bill.
    static let genericPageSize = 50

    /// Foods *as eaten* — "spaghetti with meat sauce", "chicken curry,
    /// restaurant" — where the other three carry ingredients.
    ///
    /// Requested on its own, never alongside the others. Including this value in
    /// the main request makes it fail intermittently: measured over repeated
    /// identical calls, the three stable types returned 200 twelve times out of
    /// twelve, while adding this one dropped to 5 of 12, with the rest 400s from
    /// USDA's edge rather than the API. No encoding of the space and parentheses
    /// helped — `%20`/`%28%29` gave 5/10, literal parens 7/10, `+` 4/10 — so the
    /// value itself is what trips it.
    private static let surveyDataType = "Survey (FNDDS)"

    /// Attempts for the survey request. Failures are independent at roughly 55%,
    /// so three tries lands near 90% while the main search is never at risk.
    private static let surveyAttempts = 3

    /// Datasets with no supplier behind them — whole foods and survey recipes.
    static let genericDataTypes: Set<String> = [
        "Foundation", "SR Legacy", "Survey (FNDDS)", "survey_fndds_food",
    ]

    /// FDC's `marketCountry` → Open Food Facts country tags, so a USDA branded
    /// item and an Open Food Facts one can be compared on the same footing.
    ///
    /// Nearly every FDC branded entry is "United States". Returning [] for an
    /// unrecognised or absent market leaves the food unattributed rather than
    /// asserting a country it never claimed.
    static func countryTags(forMarket market: String?) -> [String] {
        switch market?.trimmingCharacters(in: .whitespaces).lowercased() {
        case "united states": return ["united-states"]
        case "canada": return ["canada"]
        case "united kingdom": return ["united-kingdom"]
        case "australia": return ["australia"]
        case "new zealand": return ["new-zealand"]
        default: return []
        }
    }

    /// Generic foods first (Foundation and SR Legacy are lab-analyzed), then
    /// USDA's branded entries. Returns [] with no key rather than throwing —
    /// search still works through the local cache and Open Food Facts.
    ///
    /// The survey dataset is fetched as a second, independent request and appended.
    /// It is additive: when it fails the search still returns everything else,
    /// which is why it can't share the main request.
    /// `includeBranded` is the caller's call because USDA's branded set is
    /// US-only. On a British or Irish shelf every one of those items sorts into
    /// the bottom provenance band, so fetching them spends about 720 KB a search
    /// on results that appear last — where for a US user they *are* the local
    /// shelf. Open Food Facts covers branded products everywhere, with country
    /// tiers, so nothing is unreachable either way.
    func search(_ term: String, page: Int = 1, includeBranded: Bool = true,
                limit: Int = USDAClient.pageSize) async throws -> [ResolvedFood] {
        guard resolveKey() != nil else { return [] }
        let query = String(term.prefix(80)).trimmingCharacters(in: .whitespaces)
        guard query.count >= FoodSearch.minimumQueryLength else { return [] }

        async let surveyFoods = surveySearch(query, page: page, limit: limit)
        async let brandedFoods = brandedSearch(query, page: page, limit: limit,
                                               include: includeBranded)
        let generics = try await request(query, page: page,
                                         limit: Self.genericPageSize,
                                         dataTypes: Self.genericSearchDataTypes)

        var seen = Set(generics.map(\.id))
        var out = generics
        for food in await brandedFoods + (await surveyFoods)
        where seen.insert(food.id).inserted {
            out.append(food)
        }
        return out
    }

    /// Additive like the survey set, and never throwing: losing the branded items
    /// must not turn a working search into a failed one.
    private func brandedSearch(_ query: String, page: Int, limit: Int,
                               include: Bool) async -> [ResolvedFood] {
        guard include else { return [] }
        return (try? await request(query, page: page, limit: limit,
                                   dataTypes: Self.brandedDataType)) ?? []
    }

    /// The survey dataset, retried a few times and never throwing: a failure here
    /// must not turn a working search into an empty one.
    private func surveySearch(_ query: String, page: Int,
                              limit: Int) async -> [ResolvedFood] {
        for _ in 0..<Self.surveyAttempts {
            if let foods = try? await request(query, page: page, limit: limit,
                                              dataTypes: Self.surveyDataType) {
                return foods
            }
        }
        return []
    }

    private func request(_ query: String, page: Int, limit: Int,
                         dataTypes: String) async throws -> [ResolvedFood] {
        guard let key = resolveKey() else { return [] }
        var comps = URLComponents(string: "https://api.nal.usda.gov/fdc/v1/foods/search")!
        comps.queryItems = [
            .init(name: "query", value: query),
            .init(name: "pageSize", value: String(min(limit, 200))),
            .init(name: "pageNumber", value: String(max(page, 1))),
            .init(name: "dataType", value: dataTypes),
            .init(name: "api_key", value: key),
        ]

        guard let url = comps.url else { throw URLError(.badURL) }
        let response: SearchResponse = try await session.getJSON(url)
        return response.foods.compactMap(\.resolved)
    }

    /// Full record for one food, including `foodPortions` — the household
    /// measures ("1 medium", "1 cup, sliced") that search results omit.
    /// Fetched lazily when the log sheet opens rather than for every search hit,
    /// which would be one request per result.
    func detail(fdcID: Int) async throws -> ResolvedFood? {
        guard let key = resolveKey() else { return nil }
        var comps = URLComponents(string: "https://api.nal.usda.gov/fdc/v1/food/\(fdcID)")!
        comps.queryItems = [.init(name: "api_key", value: key)]
        guard let url = comps.url else { throw URLError(.badURL) }
        let food: SearchResponse.Food = try await session.getJSON(url)
        return food.resolved
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
            /// "Foundation", "SR Legacy", "Branded", "Survey (FNDDS)".
            let dataType: String?
            /// Branded items carry the market they're sold in ("United States").
            let marketCountry: String?
            let brandName: String?
            let servingSize: Double?
            let servingSizeUnit: String?
            let householdServingFullText: String?
            let foodNutrients: [Nutrient]?
            let foodPortions: [Portion]?

            /// USDA household measures. `amount` × `measureUnit`/`modifier`
            /// describes the portion, `gramWeight` is what it weighs.
            struct Portion: Decodable {
                let amount: Double?
                let modifier: String?
                let gramWeight: Double?
                let portionDescription: String?
                let measureUnit: MeasureUnit?

                struct MeasureUnit: Decodable {
                    let name: String?
                }

                /// "1 medium", "1 cup, sliced", "1 bar". USDA splits this across
                /// three optional fields with inconsistent population, so they're
                /// assembled in preference order and anything unusable is dropped.
                var resolved: FoodPortion? {
                    guard let grams = gramWeight, grams > 0 else { return nil }

                    // `measureUnit.name` is "undetermined" when USDA has none.
                    let unit = (measureUnit?.name).flatMap {
                        $0.lowercased() == "undetermined" ? nil : $0
                    }
                    let qualifier = [unit, modifier]
                        .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                        .joined(separator: ", ")

                    var label: String
                    if !qualifier.isEmpty {
                        let count = amount ?? 1
                        let countText = count == count.rounded()
                            ? String(Int(count)) : String(format: "%.2g", count)
                        label = "\(countText) \(qualifier)"
                    } else if let described = portionDescription?
                        .trimmingCharacters(in: .whitespaces), !described.isEmpty {
                        label = described
                    } else {
                        return nil
                    }
                    label = String(label.prefix(60))
                    return FoodPortion(label: label, gramWeight: grams)
                }
            }

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
                let grams = servingSizeUnit?.lowercased() == "g" ? servingSize : nil

                var portions = (foodPortions ?? []).compactMap(\.resolved)
                // Branded foods have no foodPortions but do carry a named
                // household serving ("1 bar", "2 tbsp") alongside its weight.
                if portions.isEmpty, let grams,
                   let household = householdServingFullText?
                    .trimmingCharacters(in: .whitespaces), !household.isEmpty {
                    portions = [FoodPortion(label: String(household.prefix(60)),
                                            gramWeight: grams)]
                }
                // Same measure can appear twice with different weights; keep the
                // first of each label so the picker doesn't show duplicates.
                var seenLabels: Set<String> = []
                portions = portions.filter { seenLabels.insert($0.label).inserted }

                var food = ResolvedFood(
                    id: "fdc:\(fdcId)",
                    source: .usda,
                    name: name,
                    brand: (brand?.isEmpty ?? true) ? nil : brand,
                    per100g: profile,
                    servingGrams: grams,
                    portions: portions)
                // Foundation, SR Legacy and the survey set are whole foods and
                // recipes with no supplier, so they have no country. Ranking them
                // as foreign would bury "rice, white, long-grain" under some other
                // country's own-brand.
                food.isGeneric = USDAClient.genericDataTypes.contains(dataType ?? "")
                food.countryTags = USDAClient.countryTags(forMarket: marketCountry)
                return food
            }
        }
    }
}

/// The user's own FDC key. Keychain, not UserDefaults — it is a credential.
enum USDAKeyStore {
    private static let account = "usda.apiKey"

    /// Keychain first, then a key injected at build time.
    ///
    /// The build-time value comes from `Secrets.xcconfig`, which is gitignored,
    /// through an Info.plist substitution. It exists because Keychain entries
    /// don't survive a reinstall without iCloud Keychain, and personal-team
    /// provisioning profiles expire weekly — so without it the key has to be
    /// pasted again every few days.
    ///
    /// It does mean the key reaches the app bundle and can be recovered from it.
    /// That is acceptable for a personal build of a free, per-key rate-limited,
    /// revocable API key, and is not acceptable for a distributed one — a build
    /// intended for anyone else should ship with the setting unset and rely on
    /// the settings screen.
    static var key: String? {
        if let stored = Keychain.read(account) { return stored }
        return bundledKey
    }

    /// True when the key came from the build rather than the settings screen, so
    /// the UI can say where it's coming from instead of showing an empty field.
    static var isBundled: Bool {
        Keychain.read(account) == nil && bundledKey != nil
    }

    private static var bundledKey: String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "USDAAPIKey") as? String
        else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // An unset build setting substitutes to the empty string, and the
        // placeholder is what the example file ships with.
        guard !trimmed.isEmpty, trimmed != "$(USDA_API_KEY)" else { return nil }
        return trimmed
    }

    static func save(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        trimmed.isEmpty ? Keychain.delete(account) : Keychain.write(trimmed, account: account)
    }

    static func clear() {
        Keychain.delete(account)
    }
}
