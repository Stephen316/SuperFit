import Testing
import Foundation
@testable import SuperFit

/// Runs `MetabolismEngine` and `WeightEnergyModel` against identical inputs and
/// prints where they part company.
///
/// The point is not that one is authoritative. It is that two independent
/// derivations of the same physics should agree on any input a real user can
/// produce, and every place they don't is either a bug or an undocumented
/// modelling choice. Both are worth knowing about.
struct EngineComparisonTests {

    private let height = 178.0
    private let age = 30.0
    private let activity = ActivityBaseline.moderate
    private let goal = FitnessGoal.recomposition

    /// xcodebuild does not relay the test host's stdout, so the tables are
    /// written into the host's tmp directory where they can be read off disk.
    static func emit(_ text: String, to name: String) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func basal(_ kg: Double) -> Double {
        // Mifflin-St Jeor, sex .other, matching the existing engine's midpoint.
        10 * kg + 6.25 * height - 5 * age - 78
    }

    private struct Scenario {
        let name: String
        let days: [WeightEnergyModel.Day]
    }

    /// Weigh-ins every `weighEvery` days, intake on `intakeDays` of the last 35.
    private func build(name: String, weights: [(dayAgo: Int, kg: Double)],
                       intakeKcal: Double?, intakeDays: Int = 35) -> Scenario {
        let cal = Calendar.current
        var days: [WeightEnergyModel.Day] = []
        var weightByDay: [Int: Double] = [:]
        for w in weights { weightByDay[w.dayAgo] = w.kg }
        for d in 0...35 {
            let date = cal.date(byAdding: .day, value: -d, to: .now)!
            let intake = (intakeKcal != nil && d >= 1 && d <= intakeDays) ? intakeKcal : nil
            let kg = weightByDay[d]
            guard intake != nil || kg != nil else { continue }
            days.append(.init(date: date, intakeKcal: intake, weightKg: kg))
        }
        return Scenario(name: name, days: days)
    }

    private func scenarios() -> [Scenario] {
        var out: [Scenario] = []
        let daily = (0...35).map { (dayAgo: $0, kg: 80.0) }

        out.append(build(name: "flat 80kg, intake logged daily",
                         weights: daily, intakeKcal: 2600))

        out.append(build(name: "flat 80kg, NO intake logged",
                         weights: daily, intakeKcal: nil))

        // The reported failure: one weigh-in a week ago typed 1kg light.
        var mistyped = daily
        mistyped[7] = (dayAgo: 7, kg: 79.0)
        out.append(build(name: "one weigh-in 1kg low (a week ago)",
                         weights: mistyped, intakeKcal: 2600))

        // Same slip, but weekly weigh-ins so it is a quarter of the data.
        var sparse = stride(from: 35, through: 0, by: -7).map { (dayAgo: $0, kg: 80.0) }
        sparse[4] = (dayAgo: 7, kg: 79.0)
        out.append(build(name: "sparse weekly weigh-ins, one 1kg low",
                         weights: sparse, intakeKcal: 2600))

        // A genuine cut: 0.5 kg/week down.
        out.append(build(name: "real cut, -0.5kg/wk",
                         weights: (0...35).map { (dayAgo: $0, kg: 80.0 + Double($0) * 0.5 / 7) },
                         intakeKcal: 2200))

        // A genuine bulk.
        out.append(build(name: "real bulk, +0.25kg/wk",
                         weights: (0...35).map { (dayAgo: $0, kg: 80.0 - Double($0) * 0.25 / 7) },
                         intakeKcal: 3000))

        // A single absurd entry — the typo the clamp exists for.
        var typo = daily
        typo[0] = (dayAgo: 0, kg: 95.0)
        out.append(build(name: "today's weigh-in typed 95 instead of 80",
                         weights: typo, intakeKcal: 2600))

        // Intake logged only half the days.
        out.append(build(name: "flat 80kg, intake logged 17 of 35 days",
                         weights: daily, intakeKcal: 2600, intakeDays: 17))

        // A brand-new user's first days. Overnight water swings of ~1kg between
        // consecutive mornings — nothing here is a trend.
        let firstWeek: [Double] = [80.0, 81.1, 79.9, 80.8, 80.1, 81.0, 80.2, 79.8]
        for age in [2, 3, 5, 7, 10] {
            let ws = (0..<age).map { (dayAgo: $0, kg: firstWeek[min($0, firstWeek.count - 1)]) }
            out.append(build(name: "day \(age) of use, water noise ±1kg",
                             weights: ws, intakeKcal: 2600, intakeDays: age - 1))
        }

        return out
    }

    @Test func compareAgainstExistingEngine() {
        var rows: [String] = []
        var divergences = 0

        for s in scenarios() {
            let records = s.days.map {
                DailyRecord(date: $0.date, intakeKcal: $0.intakeKcal, weightKg: $0.weightKg)
            }
            let prior = MetabolismEngine.Prior(sex: .other, ageYears: age,
                                               heightCm: height, activity: activity)
            let old = MetabolismEngine().estimate(records: records, windowDays: 30, prior: prior)
            let oldGoal = MetabolismEngine().calorieTarget(
                tdee: old, goal: goal,
                bodyweightKg: s.days.compactMap(\.weightKg).last ?? 80)

            let new = WeightEnergyModel.evaluate(days: s.days, windowDays: 30, goal: goal,
                                                 basal: basal,
                                                 activityFactor: activity.factor)

            let dTDEE = new.tdeeKcal - old.tdeeKcal
            let dGoal = new.calorieGoalKcal - oldGoal
            if abs(dGoal) >= 50 { divergences += 1 }

            rows.append(String(
                format: "%-42s old %6.0f/%6.0f   new %6.0f/%6.0f   Δtdee %+6.0f  Δgoal %+6.0f  [%@%@]",
                (s.name as NSString).utf8String!,
                old.tdeeKcal, oldGoal, new.tdeeKcal, new.calorieGoalKcal,
                dTDEE, dGoal, new.basis.rawValue,
                new.limitedBy.map { ", " + $0 } ?? ""))
        }

        var out = "=== TDEE / calorie-goal, existing vs rewrite ===\n"
        out += rows.joined(separator: "\n")
        out += "\n\ngoal differs by >= 50 kcal in \(divergences)/\(rows.count) scenarios\n"
        Self.emit(out, to: "comparison.txt")
    }

    /// Inside the first week the target must be the basal equation times the
    /// activity factor, untouched by whatever the scales happened to say.
    @Test func firstWeekUsesTheBasalEquationOnly() {
        let cal = Calendar.current
        let prior = MetabolismEngine.Prior(sex: .other, ageYears: age,
                                           heightCm: height, activity: activity)

        func tdee(days: Int, intake: Double, weights: [Double]) -> Double {
            let recs = (0..<days).map { i in
                DailyRecord(date: cal.date(byAdding: .day, value: -i, to: .now)!,
                            intakeKcal: i == 0 ? nil : intake,
                            weightKg: weights[min(i, weights.count - 1)])
            }
            return MetabolismEngine().estimate(records: recs, windowDays: 30, prior: prior).tdeeKcal
        }

        let flat = [80.0, 80.0, 80.0, 80.0, 80.0, 80.0, 80.0, 80.0, 80.0, 80.0, 80.0, 80.0]

        // The defining property: with the balance term switched off, what you
        // ate cannot move the answer. Doubling intake must change nothing.
        #expect(tdee(days: 5, intake: 2000, weights: flat)
                == tdee(days: 5, intake: 4000, weights: flat),
                "inside the first week intake must not reach the target")

        // And the answer is the equation: Mifflin-St Jeor × activity factor.
        let mifflin = (10 * 80.0 + 6.25 * height - 5 * age - 78) * activity.factor
        #expect(abs(tdee(days: 5, intake: 2600, weights: flat) - mifflin.rounded()) <= 1)

        // Past the threshold the measurement is allowed in again, so the same
        // comparison must now diverge — otherwise the gate never opens.
        #expect(tdee(days: 12, intake: 2000, weights: flat)
                != tdee(days: 12, intake: 4000, weights: flat),
                "after the first week the measured balance must take over")
    }

    /// The property that matters regardless of which implementation wins:
    /// correcting a mistyped weigh-in must put the goal back where it was.
    @Test func bothRecoverFromACorrectedWeighIn() {
        let cal = Calendar.current
        func days(weekAgo: Double) -> [WeightEnergyModel.Day] {
            (1...35).map { d in
                WeightEnergyModel.Day(
                    date: cal.date(byAdding: .day, value: -d, to: .now)!,
                    intakeKcal: 2600,
                    weightKg: d == 7 ? weekAgo : 80)
            }
        }
        func evaluate(_ ds: [WeightEnergyModel.Day]) -> (old: Double, new: Double) {
            let recs = ds.map { DailyRecord(date: $0.date, intakeKcal: $0.intakeKcal, weightKg: $0.weightKg) }
            let prior = MetabolismEngine.Prior(sex: .other, ageYears: age,
                                               heightCm: height, activity: activity)
            let e = MetabolismEngine().estimate(records: recs, windowDays: 30, prior: prior)
            let o = MetabolismEngine().calorieTarget(tdee: e, goal: goal, bodyweightKg: 80)
            let n = WeightEnergyModel.evaluate(days: ds, windowDays: 30, goal: goal,
                                              basal: basal, activityFactor: activity.factor)
            return (o, n.calorieGoalKcal)
        }

        let honest = evaluate(days(weekAgo: 80))
        let wrong = evaluate(days(weekAgo: 79))
        let fixed = evaluate(days(weekAgo: 80))

        Self.emit(String(format:
            "=== corrected weigh-in (goal kcal) ===\n"
            + "existing:  honest %.0f  mistyped %.0f  corrected %.0f\n"
            + "rewrite :  honest %.0f  mistyped %.0f  corrected %.0f\n",
            honest.old, wrong.old, fixed.old,
            honest.new, wrong.new, fixed.new), to: "corrected.txt")

        #expect(fixed.old == honest.old)
        #expect(fixed.new == honest.new)
    }
}
