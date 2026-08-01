import Testing
import Foundation
import SwiftData
@testable import SuperFit

/// Correcting a weigh-in has to move the numbers built on top of it.
///
/// The calorie and macro targets on the dashboard are not computed live — they
/// are read from a stored `MetabolicEstimateRecord`. Rebuilding only the
/// smoothed trend after an edit leaves the corrected weight showing in the
/// weight list while every target keeps quoting the old one, which is the
/// failure these tests exist to catch.
@MainActor
struct WeightDerivedRefreshTests {

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(AppSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        return ModelContext(container)
    }

    /// 40 days of weigh-ins ending today, so the 30-day window is well covered.
    @discardableResult
    private func seed(_ context: ModelContext, endingAt last: Double = 82) -> [BodyMetrics] {
        let profile = UserProfile()
        profile.heightCm = 178
        context.insert(profile)

        var rows: [BodyMetrics] = []
        for i in stride(from: 39, through: 0, by: -1) {
            let date = Calendar.current.date(byAdding: .day, value: -i, to: .now)!
            let m = BodyMetrics(date: date, weightKg: last + Double(i) * 0.05)
            context.insert(m)
            rows.append(m)
        }
        return rows
    }

    private func estimate(_ context: ModelContext, window: Int = 30) throws -> MetabolicEstimateRecord {
        let all = (try? context.fetch(FetchDescriptor<MetabolicEstimateRecord>())) ?? []
        return try #require(all.first { $0.windowDays == window })
    }

    @Test func editingAWeighInMovesTheStoredEstimate() throws {
        let context = try makeContext()
        let rows = seed(context)
        AggregationService(context: context).refreshWeightDerived()

        let before = try estimate(context)
        let basalBefore = before.basalKcal
        let tdeeBefore = before.tdeeKcal
        #expect(basalBefore > 0)

        // A correction of the kind the edit sheet makes: mistyped 82, meant 95.
        rows.last!.weightKg = 95
        AggregationService(context: context).refreshWeightDerived()

        let after = try estimate(context)
        #expect(after.basalKcal > basalBefore,
                "basal is derived from the smoothed weight, so it has to rise")
        #expect(after.tdeeKcal > tdeeBefore,
                "TDEE is the basal estimate times the activity factor")
    }

    @Test func deletingAWeighInMovesTheStoredEstimate() throws {
        let context = try makeContext()
        seed(context)
        AggregationService(context: context).refreshWeightDerived()
        let baseline = try estimate(context).basalKcal

        // Log a heavy outlier, then remove it again: the estimate has to follow
        // the weight series in both directions.
        let outlier = BodyMetrics(date: .now, weightKg: 95)
        context.insert(outlier)
        AggregationService(context: context).refreshWeightDerived()
        let withOutlier = try estimate(context).basalKcal
        #expect(withOutlier > baseline)

        context.delete(outlier)
        AggregationService(context: context).refreshWeightDerived()
        #expect(abs(try estimate(context).basalKcal - baseline) < 0.5,
                "deleting the outlier must put the estimate back where it was")
    }

    /// The trend rebuild on its own is what the weight screen used to do, and it
    /// is exactly what left the dashboard stale.
    @Test func trendRebuildAloneDoesNotRefreshTheEstimate() throws {
        let context = try makeContext()
        let rows = seed(context)
        AggregationService(context: context).refreshWeightDerived()
        let before = try estimate(context).basalKcal

        rows.last!.weightKg = 95
        AggregationService(context: context).fillWeightTrend()

        // fillWeightTrend touches only BodyMetrics. If this ever starts
        // refreshing the estimate too, refreshWeightDerived is redundant.
        #expect(try estimate(context).basalKcal == before)
    }

    /// Two weigh-ins on one day used to be resolved by whichever the unsorted
    /// fetch happened to yield last, so a second weigh-in could leave the
    /// estimate sitting on the earlier number — indistinguishable, from the
    /// dashboard, from nothing having recalculated.
    @Test func bothWeighInsOnADayCountTowardsTheEstimate() throws {
        let context = try makeContext()
        seed(context)
        AggregationService(context: context).refreshWeightDerived()
        let oneEntry = try estimate(context).basalKcal

        context.insert(BodyMetrics(date: .now, weightKg: 95))
        AggregationService(context: context).refreshWeightDerived()
        let averaged = try estimate(context).basalKcal
        #expect(averaged > oneEntry, "the day's mean has risen, so basal must too")

        // Order of insertion must not decide the answer.
        let reversed = try makeContext()
        let rows = seed(reversed)
        reversed.insert(BodyMetrics(date: rows.last!.date, weightKg: 95))
        AggregationService(context: reversed).refreshWeightDerived()
        #expect(abs(try estimate(reversed).basalKcal - averaged) < 0.5)
    }

    /// Recovery and the cyclical baselines are driven by sleep and HRV; a
    /// weigh-in cannot move them, so the weight path must not pay for them.
    @Test func refreshLeavesRecoveryAlone() throws {
        let context = try makeContext()
        seed(context)
        AggregationService(context: context).refreshWeightDerived()
        let recoveries = (try? context.fetch(FetchDescriptor<RecoveryScoreRecord>())) ?? []
        #expect(recoveries.isEmpty)
    }
}
