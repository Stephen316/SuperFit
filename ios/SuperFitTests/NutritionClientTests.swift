import Testing
import Foundation
@testable import SuperFit

final class StubProtocol: URLProtocol {
    nonisolated(unsafe) static var responder: ((URL) -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let (status, data) = Self.responder?(url) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let response = HTTPURLResponse(url: url, statusCode: status,
                                       httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        return URLSession(configuration: config)
    }
}

private let offProductJSON = """
{
  "status": 1,
  "product": {
    "code": "3017620422003",
    "product_name": "Nutella",
    "brands": "Ferrero, Nutella",
    "serving_quantity": "15",
    "nutriments": {
      "energy-kcal_100g": 539,
      "proteins_100g": 6.3,
      "carbohydrates_100g": 57.5,
      "fat_100g": 30.9,
      "fiber_100g": 3.4
    }
  }
}
""".data(using: .utf8)!

private let usdaSearchJSON = """
{
  "foods": [
    {
      "fdcId": 171077,
      "description": "Chicken, broilers or fryers, breast, meat only, cooked, roasted",
      "foodNutrients": [
        {"nutrientId": 1008, "value": 165},
        {"nutrientId": 1003, "value": 31.0},
        {"nutrientId": 1004, "value": 3.57},
        {"nutrientId": 1005, "value": 0},
        {"nutrientId": 1079, "value": 0},
        {"nutrientId": 1089, "value": 1.04},
        {"nutrientId": 1092, "value": 256},
        {"nutrientId": 1093, "value": 74}
      ]
    },
    {
      "fdcId": 999001,
      "description": "Protein Bar, Chocolate",
      "brandName": "SomeBrand",
      "servingSize": 60,
      "servingSizeUnit": "g",
      "foodNutrients": [
        {"nutrientId": 1008, "value": 380},
        {"nutrientId": 1003, "value": 33}
      ]
    },
    {
      "fdcId": 999002,
      "description": "Broken entry with no energy",
      "foodNutrients": [{"nutrientId": 1003, "value": 12}]
    }
  ]
}
""".data(using: .utf8)!

@Suite(.serialized) struct NutritionClientTests {

    @Test func offProductMapsNutrimentsAndStringServing() async throws {
        StubProtocol.responder = { _ in (200, offProductJSON) }
        let client = OpenFoodFactsClient(session: StubProtocol.session())
        let food = try await client.product(barcode: "3017620422003")

        let f = try #require(food)
        #expect(f.name == "Nutella")
        #expect(f.brand == "Ferrero")                 // first of comma list
        #expect(f.per100g.kcal == 539)
        #expect(f.per100g.proteinG == 6.3)
        #expect(f.servingGrams == 15)                 // decoded from a STRING
        #expect(f.source == .openFoodFacts)
    }

    @Test func offRejectsShortOrNonNumericBarcodes() async throws {
        StubProtocol.responder = { _ in (200, offProductJSON) }
        let client = OpenFoodFactsClient(session: StubProtocol.session())
        #expect(try await client.product(barcode: "123") == nil)
        #expect(try await client.product(barcode: "abcdefgh") == nil)
    }

    @Test func usdaDecodesMacrosAndMicros() async throws {
        USDAKeyStore.save("test-key")
        defer { USDAKeyStore.clear() }
        StubProtocol.responder = { _ in (200, usdaSearchJSON) }
        let client = USDAClient(session: StubProtocol.session())

        let foods = try await client.search("chicken breast")
        let chicken = try #require(foods.first { $0.id == "fdc:171077" })
        #expect(chicken.per100g.kcal == 165)
        #expect(chicken.per100g.proteinG == 31.0)
        #expect(chicken.source == .usda)
        #expect(chicken.per100g.micros[Micronutrient.iron.rawValue] == 1.04)
        #expect(chicken.per100g.micros[Micronutrient.potassium.rawValue] == 256)
        #expect(chicken.per100g.micros[Micronutrient.sodium.rawValue] == 74)
    }

    @Test func usdaKeepsBrandAndGramServing() async throws {
        USDAKeyStore.save("test-key")
        defer { USDAKeyStore.clear() }
        StubProtocol.responder = { _ in (200, usdaSearchJSON) }
        let bar = try await USDAClient(session: StubProtocol.session())
            .search("protein bar").first { $0.id == "fdc:999001" }
        #expect(bar?.brand == "SomeBrand")
        #expect(bar?.servingGrams == 60)
    }

    /// An entry with no energy value is unusable for logging — drop it rather
    /// than surfacing a food that reads as 0 kcal.
    @Test func usdaDropsEntriesWithoutEnergy() async throws {
        USDAKeyStore.save("test-key")
        defer { USDAKeyStore.clear() }
        StubProtocol.responder = { _ in (200, usdaSearchJSON) }
        let foods = try await USDAClient(session: StubProtocol.session()).search("broken")
        #expect(!foods.contains { $0.id == "fdc:999002" })
        #expect(foods.count == 2)
    }

    /// The key is injected rather than cleared from the Keychain: under the test
    /// runner `Bundle.main` is the host app, which carries the build-time key, so
    /// clearing the Keychain alone no longer yields a key-less client.
    @Test func usdaReturnsNothingWithoutAKey() async throws {
        USDAKeyStore.clear()
        StubProtocol.responder = { _ in (200, usdaSearchJSON) }
        let client = USDAClient(session: StubProtocol.session(), key: { nil })
        #expect(try await client.search("chicken").isEmpty)
        #expect(!client.hasKey)
    }

    /// A build-time key is a fallback, never an override: someone who pastes a
    /// key in Settings expects that key to be the one used.
    @Test func theKeychainWinsOverTheBundledKey() {
        USDAKeyStore.save("keychain-key")
        defer { USDAKeyStore.clear() }
        #expect(USDAKeyStore.key == "keychain-key")
        #expect(!USDAKeyStore.isBundled)
    }

    // MARK: What USDA is asked for

    /// The generic sets are asked for on their own and wide. Mixed into one
    /// 25-result request they lost outright: "milk", "chocolate" and "yoghurt"
    /// each came back with no generic entries at all, so plain milk could never
    /// be ranked up because it was never in the response.
    @Test func genericsAreRequestedSeparatelyAndWide() async throws {
        USDAKeyStore.save("test-key")
        defer { USDAKeyStore.clear() }
        nonisolated(unsafe) var queries: [String] = []
        StubProtocol.responder = { url in
            queries.append(url.query?.removingPercentEncoding ?? "")
            return (200, usdaSearchJSON)
        }
        _ = try await USDAClient(session: StubProtocol.session())
            .search("rice", includeBranded: false)

        let generic = try #require(queries.first { $0.contains("Foundation") })
        #expect(generic.contains("SR Legacy"))
        #expect(generic.contains("pageSize=\(USDAClient.genericPageSize)"))
        // Wider than the ordinary page, or the real food stays off the end of it.
        #expect(USDAClient.genericPageSize > USDAClient.pageSize)
    }

    /// USDA's branded set is US-only. Off a US shelf every one of those items
    /// sorts into the bottom provenance band, so fetching them spends bandwidth
    /// on results that appear last.
    @Test func brandedIsSkippedWhenItIsNotTheLocalShelf() async throws {
        USDAKeyStore.save("test-key")
        defer { USDAKeyStore.clear() }
        nonisolated(unsafe) var queries: [String] = []
        StubProtocol.responder = { url in
            queries.append(url.query?.removingPercentEncoding ?? "")
            return (200, usdaSearchJSON)
        }
        _ = try await USDAClient(session: StubProtocol.session())
            .search("rice", includeBranded: false)
        #expect(!queries.contains { $0.contains("dataType=Branded") })
    }

    @Test func brandedIsFetchedWhenItIsTheLocalShelf() async throws {
        USDAKeyStore.save("test-key")
        defer { USDAKeyStore.clear() }
        nonisolated(unsafe) var queries: [String] = []
        StubProtocol.responder = { url in
            queries.append(url.query?.removingPercentEncoding ?? "")
            return (200, usdaSearchJSON)
        }
        _ = try await USDAClient(session: StubProtocol.session())
            .search("rice", includeBranded: true)
        #expect(queries.contains { $0.contains("dataType=Branded") })
    }

    /// Losing the branded request must not empty a working search, the same rule
    /// the survey set follows.
    @Test func aFailingBrandedRequestStillLeavesTheGenerics() async throws {
        USDAKeyStore.save("test-key")
        defer { USDAKeyStore.clear() }
        StubProtocol.responder = { url in
            let q = url.query?.removingPercentEncoding ?? ""
            return q.contains("dataType=Branded") ? (503, Data()) : (200, usdaSearchJSON)
        }
        let foods = try await USDAClient(session: StubProtocol.session())
            .search("chicken", includeBranded: true)
        #expect(!foods.isEmpty)
    }

    @Test func usdaRejectsShortQueries() async throws {
        USDAKeyStore.save("test-key")
        defer { USDAKeyStore.clear() }
        StubProtocol.responder = { _ in (200, usdaSearchJSON) }
        #expect(try await USDAClient(session: StubProtocol.session()).search("c").isEmpty)
    }

    @Test func serverErrorThrowsInsteadOfDecodingGarbage() async {
        StubProtocol.responder = { _ in (500, Data("oops".utf8)) }
        let client = OpenFoodFactsClient(session: StubProtocol.session())
        await #expect(throws: (any Error).self) {
            _ = try await client.product(barcode: "3017620422003")
        }
    }

    @Test func portionScalingIsLinear() {
        let food = ResolvedFood(id: "x", source: .custom, name: "Oats", brand: nil,
                                per100g: NutrientProfile(kcal: 380, proteinG: 13,
                                                         carbsG: 68, fatG: 7, fibreG: 10),
                                servingGrams: 40)
        let p = food.scaled(grams: 40)
        #expect(abs(p.kcal - 152) < 0.01)
        #expect(abs(p.proteinG - 5.2) < 0.01)
    }
}
