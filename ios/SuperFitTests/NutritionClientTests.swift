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
      "description": "CHICKEN, BROILERS OR FRYERS, BREAST, MEAT ONLY, COOKED, ROASTED",
      "foodNutrients": [
        {"nutrientNumber": "208", "value": 165},
        {"nutrientNumber": "203", "value": 31.0},
        {"nutrientNumber": "204", "value": 3.6},
        {"nutrientNumber": "205", "value": 0},
        {"nutrientNumber": "291", "value": 0}
      ]
    },
    {
      "fdcId": 999999,
      "description": "Entry with no energy value",
      "foodNutrients": [{"nutrientNumber": "203", "value": 10}]
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

    @Test func usdaMapsNutrientNumbersAndDropsEnergylessRows() async throws {
        StubProtocol.responder = { _ in (200, usdaSearchJSON) }
        let client = USDAClient(session: StubProtocol.session(), apiKey: "test")
        let foods = try await client.search("chicken breast")

        #expect(foods.count == 1)                     // energyless row dropped
        let f = try #require(foods.first)
        #expect(f.id == "fdc:171077")
        #expect(f.per100g.kcal == 165)
        #expect(f.per100g.proteinG == 31.0)
        #expect(f.per100g.fatG == 3.6)
        #expect(f.source == .usda)
    }

    @Test func usdaWithoutKeyReturnsEmptyNotError() async throws {
        let client = USDAClient(session: StubProtocol.session(), apiKey: nil)
        #expect(try await client.search("anything").isEmpty)
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
