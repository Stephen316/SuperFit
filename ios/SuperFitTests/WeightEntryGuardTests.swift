import Testing
import Foundation
@testable import SuperFit

/// A wrong weigh-in must not be able to destroy the calorie estimate.
///
/// TDEE inference treats a weight change as stored or burned energy, so a bad
/// number doesn't give a slightly wrong answer — it gives an absurd one. Measured
/// before the clamp: one mistyped weigh-in of 89 kg instead of 80 produced a
/// +9 kg/week trend and a TDEE of **452 kcal**.
struct WeightEntryGuardTests {

    private let engine = MetabolismEngine()
    private let cal = Calendar(identifier: .gregorian)

    private func records(weighIns: [(Int, Double)], intake: Double = 2400,
                         days: Int = 30) -> [DailyRecord] {
        let now = Date()
        let byDay = Dictionary(uniqueKeysWithValues: weighIns)
        return (-(days - 1)...0).map { d in
            DailyRecord(date: cal.date(byAdding: .day, value: d, to: now)!,
                        intakeKcal: intake, weightKg: byDay[d])
        }
    }

    private var prior: MetabolismEngine.Prior {
        .init(sex: .male, ageYears: 30, heightCm: 180, activity: .moderate,
              avgActiveEnergyKcal: 400, leanMassKg: nil)
    }

    private func estimate(_ weighIns: [(Int, Double)], intake: Double = 2400) -> TDEEEstimate {
        engine.estimate(records: records(weighIns: weighIns, intake: intake),
                        windowDays: 30, prior: prior)
    }

    // MARK: The reported failure

    /// A single mistyped digit used to collapse the estimate. It must now land in
    /// the same region as the same person weighing steadily.
    @Test func aMistypedWeighInCannotCollapseTheEstimate() {
        let typo = estimate([(-7, 80), (0, 89)])
        let flat = estimate([(-7, 80), (0, 80)])
        #expect(typo.tdeeKcal > 1500, "typo produced TDEE \(typo.tdeeKcal)")
        #expect(abs(typo.tdeeKcal - flat.tdeeKcal) < 400)
    }

    /// Absurd in the other direction too — a weight typed far too low reads as a
    /// huge deficit and would inflate TDEE just as badly.
    @Test func aWeighInTypedFarTooLowCannotInflateTheEstimate() {
        let typo = estimate([(-7, 80), (0, 68)])
        let flat = estimate([(-7, 80), (0, 80)])
        #expect(abs(typo.tdeeKcal - flat.tdeeKcal) < 400)
    }

    // MARK: Real trends still get through

    /// The clamp must not flatten genuine progress. A kilo a week on an 80 kg
    /// frame is 1.25% — aggressive but real, and under the limit.
    @Test func aGenuineWeeklyGainStillMovesTheEstimate() {
        let gaining = estimate([(-7, 80), (0, 81)])
        let flat = estimate([(-7, 80), (0, 80)])
        // Gaining on the same intake means a lower true expenditure.
        #expect(gaining.tdeeKcal < flat.tdeeKcal)
        #expect(flat.tdeeKcal - gaining.tdeeKcal > 100)
    }

    @Test func aGenuineWeeklyLossStillMovesTheEstimate() {
        let losing = estimate([(-7, 80), (0, 79)])
        let flat = estimate([(-7, 80), (0, 80)])
        #expect(losing.tdeeKcal > flat.tdeeKcal)
    }

    /// The clamp scales with bodyweight, so it isn't stricter on a larger person.
    @Test func theLimitScalesWithBodyweight() {
        // 1.5 kg/week is 1.5% of 100 kg — at the limit, so it passes through.
        let heavy = estimate([(-7, 100), (0, 101.5)])
        let heavyFlat = estimate([(-7, 100), (0, 100)])
        #expect(heavyFlat.tdeeKcal - heavy.tdeeKcal > 200)
    }

    /// What the user sees is what they logged: only the energy inference is
    /// clamped, never the reported trend.
    @Test func theReportedTrendIsNotClamped() {
        #expect(abs(estimate([(-7, 80), (0, 89)]).trendSlopeKgPerWeek - 9) < 0.01)
    }

    // MARK: Existing protections still hold

    /// Spread weigh-ins already survive one bad reading, because Theil–Sen takes
    /// the median of pairwise slopes rather than fitting through the outlier.
    @Test func aSingleOutlierAmongManyWeighInsIsIgnored() {
        let e = estimate([(-28, 80), (-21, 80), (-14, 80), (-7, 80), (0, 89)])
        #expect(abs(e.trendSlopeKgPerWeek) < 0.5)
    }

    /// However wrong the input, the prescription never drops below basal.
    @Test func theTargetNeverFallsBelowBasal() {
        for weights in [[(-7, 80.0), (0, 95.0)], [(-7, 80.0), (0, 60.0)], [(-7, 80.0), (0, 80.0)]] {
            let e = estimate(weights)
            let target = engine.calorieTarget(tdee: e, goal: .fatLoss, bodyweightKg: 80)
            #expect(target >= e.basalKcal, "target \(target) below basal \(e.basalKcal)")
        }
    }
}
