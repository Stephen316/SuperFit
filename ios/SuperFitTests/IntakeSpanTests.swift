import Testing
import Foundation
@testable import SuperFit

/// The intake average is taken over calendar days, not over days that happen to
/// carry a record — so a weighing habit cannot move it.
struct IntakeSpanTests {

    private let cal = Calendar(identifier: .gregorian)
    private let start = Date(timeIntervalSince1970: 1_700_000_000)
    private let prior = MetabolismEngine.Prior(sex: .male, ageYears: 30,
                                               heightCm: 180, activity: .moderate)

    private var asOf: Date { cal.date(byAdding: .day, value: 30, to: start)! }

    /// Food logged for the first `loggedDays` days only; weight every `weighEvery`.
    private func estimate(weighEvery: Int,
                          loggedDays: Int = 15,
                          intake: (Int) -> Double) -> TDEEEstimate {
        var records: [DailyRecord] = []
        for d in 0..<30 {
            let logged = d < loggedDays ? intake(d) : nil
            let weighed = d.isMultiple(of: weighEvery) ? 80.0 : nil
            if logged == nil && weighed == nil { continue }
            records.append(DailyRecord(date: cal.date(byAdding: .day, value: d, to: start)!,
                                       intakeKcal: logged, weightKg: weighed))
        }
        return MetabolismEngine().estimate(records: records, windowDays: 30,
                                           prior: prior, asOf: asOf)
    }

    /// The bug, in one assertion. Identical eating and identical weights, and the
    /// only difference is how often the scale was used.
    ///
    /// Measured before the fix: 2590 kcal weighing daily against 2644 weighing
    /// weekly, a 61 kcal gap in TDEE. The unlogged second half was imputed from
    /// the declining trend for every day that carried a weigh-in, so a daily
    /// weigher gave the trend 15 votes and a weekly weigher 2.
    @Test func weighInFrequencyDoesNotMoveTheIntakeAverage() {
        let declining = { (d: Int) in 2800 - 20 * Double(d) }
        let daily = estimate(weighEvery: 1, intake: declining)
        let weekly = estimate(weighEvery: 7, intake: declining)

        #expect(abs(daily.avgIntakeKcal - weekly.avgIntakeKcal) < 1,
                "\(daily.avgIntakeKcal) against \(weekly.avgIntakeKcal)")
    }

    /// The fix must not have quietly turned imputation off. A declining intake
    /// with the back half unlogged has to read *below* the mean of the days that
    /// were logged — that projection is the whole reason the code exists.
    @Test func theTrendIsStillProjectedAcrossUnloggedDays() {
        let declining = { (d: Int) in 2800 - 20 * Double(d) }
        // Mean of the 15 logged days: 2800 … 2520, so 2660.
        let loggedMean = (0..<15).map(declining).reduce(0, +) / 15
        let estimated = estimate(weighEvery: 3, intake: declining).avgIntakeKcal
        #expect(estimated < loggedMean - 20,
                "imputation should pull the average down: \(estimated) vs \(loggedMean)")
    }

    /// Flat intake has no trend to project, so the guard falls back to the flat
    /// mean and every weighing habit agrees. This held before the fix too — it is
    /// the control that showed the defect only appears on a real trend.
    @Test func flatIntakeIsUnaffectedByWeighInFrequency() {
        let flat = { (_: Int) in 2500.0 }
        #expect(estimate(weighEvery: 1, intake: flat).avgIntakeKcal == 2500)
        #expect(estimate(weighEvery: 7, intake: flat).avgIntakeKcal == 2500)
    }

    /// The span starts at the user's first record, not `windowDays` ago, so
    /// someone a fortnight into using the app does not have two weeks of intake
    /// invented from before they arrived.
    @Test func theSpanDoesNotReachBackBeforeTheFirstRecord() {
        var records: [DailyRecord] = []
        for d in 20..<30 {
            records.append(DailyRecord(date: cal.date(byAdding: .day, value: d, to: start)!,
                                       intakeKcal: 2500, weightKg: 80))
        }
        let e = MetabolismEngine().estimate(records: records, windowDays: 30,
                                            prior: prior, asOf: asOf)
        // Ten logged days at 2500 across an eleven-day span: no invented history
        // dragging the mean toward a projected line.
        #expect(abs(e.avgIntakeKcal - 2500) < 1, "got \(e.avgIntakeKcal)")
    }
}
