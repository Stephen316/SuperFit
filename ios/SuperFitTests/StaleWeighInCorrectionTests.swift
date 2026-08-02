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

    /// Three weigh-ins across four weeks at a genuinely stable weight, with
    /// intake logged every day so the estimate is measurement-driven rather than
    /// the prior. Returns the earliest weigh-in — the one that gets mistyped.
    ///
    /// **Deliberately sparse.** Theil–Sen takes the median of every pairwise
    /// slope, so a weekly series of six weigh-ins absorbs one bad number
    /// entirely: measured on this engine, the slope stays at exactly 0.00000 and
    /// TDEE moves only by rounding. A single mistyped entry has leverage only
    /// when there are few enough weigh-ins for it to reach the median — which is
    /// the case for someone who steps on the scale every couple of weeks, and
    /// the case this was reported from. Typed low and followed by normal
    /// readings, it reads as a gain across the window.
    ///
    /// Age is pinned rather than left to `UserProfile`'s default. It is a term
    /// in Mifflin-St Jeor, so it decides whether the prior sits above or below
    /// logged intake — and a test whose direction depends on that is a test that
    /// silently changes meaning when the default does.
    private func seed(_ context: ModelContext) -> BodyMetrics {
        let cal = Calendar.current
        let profile = UserProfile()
        profile.birthDate = cal.date(byAdding: .year, value: -30, to: .now)!
        context.insert(profile)

        for d in 1...35 {
            let day = cal.date(byAdding: .day, value: -d, to: .now)!
            let log = NutritionLog(date: day, meal: .lunch)
            log.kcal = intake
            context.insert(log)
        }

        var earliest: BodyMetrics!
        for d in [28, 14, 0] {
            let day = cal.date(byAdding: .day, value: -d, to: .now)!
            let m = BodyMetrics(date: day, weightKg: 80)
            context.insert(m)
            if d == 28 { earliest = m }
        }
        return earliest
    }

    private func tdee(_ context: ModelContext) throws -> Double {
        let all = (try? context.fetch(FetchDescriptor<MetabolicEstimateRecord>())) ?? []
        return try #require(all.first { $0.windowDays == 30 }).tdeeKcal
    }

    @Test func correctingAMistypedWeighInRestoresTheTarget() throws {
        let context = try makeContext()
        let earliest = seed(context)
        let service = AggregationService(context: context)

        service.refreshWeightDerived()
        let honest = try tdee(context)

        // The slip: 79 typed where 80 was meant, four weeks ago.
        earliest.weightKg = 79
        service.refreshWeightDerived()
        let corrupted = try tdee(context)
        // A margin, not just `<`. The point is that the estimate moves by an
        // amount a person would notice — measured at ~210 kcal — rather than by
        // the kilocalorie or two that rounding can produce on its own.
        #expect(corrupted < honest - 100,
                "a phantom gain has to read as a smaller energy requirement: \(corrupted) against \(honest)")

        // The correction, exactly as the edit sheet applies it.
        earliest.weightKg = 80
        service.refreshWeightDerived()
        let restored = try tdee(context)

        // Correcting the entry must return TDEE to where it was, not leave it
        // part-way. This is the reported bug: the estimate is stored, so an edit
        // that doesn't trigger a recompute leaves the old number on the
        // dashboard indefinitely.
        #expect(abs(restored - honest) < 1, "\(restored) against \(honest)")
    }

    /// Deleting the bad entry outright is the other route the dialog offers.
    @Test func deletingAMistypedWeighInRestoresTheTarget() throws {
        let context = try makeContext()
        let earliest = seed(context)
        let service = AggregationService(context: context)

        service.refreshWeightDerived()
        let honest = try tdee(context)

        earliest.weightKg = 79
        service.refreshWeightDerived()
        #expect(try tdee(context) < honest - 100)

        context.delete(earliest)
        service.refreshWeightDerived()
        // One weigh-in fewer over a shorter span, so confidence drops and the
        // number doesn't land exactly back — but the phantom gain is gone.
        #expect(try tdee(context) > honest - 100)
    }
}
