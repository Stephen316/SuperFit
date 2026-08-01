import Testing
import Foundation
import SwiftData
@testable import SuperFit

/// The reported failure, reproduced end to end: a weigh-in entered 1 kg too low
/// a week ago drags the inferred trend into an apparent gain, and an apparent
/// gain of 1 kg/week subtracts ~1,100 kcal/day from TDEE. Correcting the entry
/// has to give those calories back.
@MainActor
struct StaleWeighInCorrectionTests {

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(AppSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        return ModelContext(container)
    }

    private let intake = 2600.0

    /// Weekly weigh-ins at a genuinely stable weight, with intake logged every
    /// day so the estimate is measurement-driven rather than the prior.
    /// Returns the weigh-in from seven days ago — the one that gets mistyped.
    private func seed(_ context: ModelContext) -> BodyMetrics {
        let cal = Calendar.current
        context.insert(UserProfile())

        for d in 1...35 {
            let day = cal.date(byAdding: .day, value: -d, to: .now)!
            let log = NutritionLog(date: day, meal: .lunch)
            log.kcal = intake
            context.insert(log)
        }

        var weekAgo: BodyMetrics!
        for d in stride(from: 35, through: 0, by: -7) {
            let day = cal.date(byAdding: .day, value: -d, to: .now)!
            let m = BodyMetrics(date: day, weightKg: 80)
            context.insert(m)
            if d == 7 { weekAgo = m }
        }
        return weekAgo
    }

    private func tdee(_ context: ModelContext) throws -> Double {
        let all = (try? context.fetch(FetchDescriptor<MetabolicEstimateRecord>())) ?? []
        return try #require(all.first { $0.windowDays == 30 }).tdeeKcal
    }

    @Test func correctingAMistypedWeighInRestoresTheTarget() throws {
        let context = try makeContext()
        let weekAgo = seed(context)
        let service = AggregationService(context: context)

        service.refreshWeightDerived()
        let honest = try tdee(context)

        // The slip: 79 typed where 80 was meant, a week ago.
        weekAgo.weightKg = 79
        service.refreshWeightDerived()
        let corrupted = try tdee(context)
        #expect(corrupted < honest,
                "a phantom gain has to read as a smaller energy requirement")

        // The correction, exactly as the edit sheet applies it.
        weekAgo.weightKg = 80
        service.refreshWeightDerived()
        let restored = try tdee(context)

        // Correcting the entry must return TDEE to where it was, not leave it
        // part-way.
        #expect(abs(restored - honest) < 1, "\(restored) against \(honest)")
    }

    /// Deleting the bad entry outright is the other route the dialog offers.
    @Test func deletingAMistypedWeighInRestoresTheTarget() throws {
        let context = try makeContext()
        let weekAgo = seed(context)
        let service = AggregationService(context: context)

        service.refreshWeightDerived()
        let honest = try tdee(context)

        weekAgo.weightKg = 79
        service.refreshWeightDerived()
        #expect(try tdee(context) < honest)

        context.delete(weekAgo)
        service.refreshWeightDerived()
        // One weigh-in fewer, so not identical — but the phantom gain is gone.
        #expect(try tdee(context) > honest - 200)
    }
}
