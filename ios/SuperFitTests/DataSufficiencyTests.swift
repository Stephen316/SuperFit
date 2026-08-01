import Testing
import Foundation
@testable import SuperFit

/// When is there enough data to trust a measured TDEE?
///
/// The answer is not a day count. It is the standard error of the measurement
/// weighed against the standard error of the prior, and these tests pin the
/// behaviour that formula is supposed to produce — above all that missing a
/// weigh-in costs you precision rather than resetting you.
struct DataSufficiencyTests {

    private let engine = MetabolismEngine()
    private let cal = Calendar(identifier: .gregorian)

    private var prior: MetabolismEngine.Prior {
        .init(sex: .male, ageYears: 30, heightCm: 180, activity: .moderate)
    }

    /// `weighInEvery` days, over `days`, on a genuinely flat 80 kg.
    private func records(days: Int, weighInEvery: Int = 1,
                         intakeEvery: Int = 1, intake: Double = 2600,
                         noise: Double = 0) -> [DailyRecord] {
        let now = Date()
        return (0..<days).reversed().map { ago in
            let wiggle = noise == 0 ? 0 : sin(Double(ago) * 12.9898) * noise
            return DailyRecord(
                date: cal.date(byAdding: .day, value: -ago, to: now)!,
                intakeKcal: ago % intakeEvery == 0 ? intake : nil,
                weightKg: ago % weighInEvery == 0 ? 80 + wiggle : nil)
        }
    }

    private func confidence(_ recs: [DailyRecord]) -> Double {
        engine.estimate(records: recs, windowDays: 30, prior: prior).confidence
    }

    // MARK: The bounds

    @Test func belowTheBoundsTheMeasurementGetsNoVote() {
        // One weigh-in: no line at all.
        #expect(confidence(records(days: 20, weighInEvery: 99)) == 0)
        // Weigh-ins bunched inside three days: no leverage, whatever the count.
        #expect(confidence(records(days: 3)) == 0)
        // Weight but effectively no food logged: nothing to difference against.
        #expect(confidence(records(days: 20, intakeEvery: 99)) == 0)
    }

    @Test func confidenceGrowsWithHistory() {
        let week2 = confidence(records(days: 14, noise: 0.5))
        let week4 = confidence(records(days: 28, noise: 0.5))
        let week8 = confidence(records(days: 56, noise: 0.5))
        #expect(week2 < week4)
        #expect(week4 < week8)
        #expect(week8 < 1, "self-report error keeps this short of certainty")
    }

    // MARK: Skipped days

    /// The point of the rewrite: a gap costs leverage, not the whole estimate.
    @Test func skippingWeighInsDegradesGracefully() {
        let daily = confidence(records(days: 28, weighInEvery: 1, noise: 0.5))
        let everyOther = confidence(records(days: 28, weighInEvery: 2, noise: 0.5))
        let weekly = confidence(records(days: 28, weighInEvery: 7, noise: 0.5))

        #expect(daily > everyOther)
        #expect(everyOther > weekly)
        // Weighing weekly for a month is thin, but it is not nothing — the old
        // day-count gate would have treated it identically to daily weighing.
        #expect(weekly > 0.05, "weekly weigh-ins still carry signal: \(weekly)")
    }

    /// A single missed day must barely register.
    @Test func oneMissedWeighInIsNearlyFree() {
        let full = records(days: 28, noise: 0.5)
        var gapped = full
        gapped[14] = DailyRecord(date: full[14].date, intakeKcal: full[14].intakeKcal,
                                 weightKg: nil)
        let before = confidence(full)
        let after = confidence(gapped)
        #expect(after > before * 0.95, "one gap cost \(before - after)")
    }

    /// Sparse *food* logging has to cost confidence too — the weight trend alone
    /// cannot say what was eaten.
    @Test func sparseFoodLoggingCostsConfidence() {
        let logged = confidence(records(days: 28, intakeEvery: 1, noise: 0.5))
        let halfLogged = confidence(records(days: 28, intakeEvery: 2, noise: 0.5))
        #expect(logged > halfLogged)
    }

    // MARK: Noise

    /// Two people with identical schedules but different scales: the one whose
    /// weight swings more gets less confidence, because their slope is less
    /// pinned down.
    @Test func noisierWeighInsEarnLessConfidence() {
        let steady = confidence(records(days: 28, noise: 0.2))
        let swingy = confidence(records(days: 28, noise: 1.5))
        #expect(steady > swingy)
    }

    /// How many consecutive days of logging it actually takes.
    ///
    /// Emits the sweep so the answer is measured rather than asserted from
    /// memory, and pins the headline figures so a model change has to restate
    /// them deliberately.
    @Test func daysRequiredForAReliableTDEE() {
        // Confidence 0.5 is the crossover: the measurement outweighs the prior.
        // 0.8 is where the prior has essentially stopped mattering.
        func firstDay(noise: Double, reaching target: Double) -> Int? {
            (3...30).first { confidence(records(days: $0, noise: noise)) >= target }
        }

        func pad(_ s: String, _ w: Int) -> String {
            String(repeating: " ", count: max(0, w - s.count)) + s
        }
        func f(_ v: Double, _ dp: Int, _ w: Int) -> String {
            pad(String(format: "%.\(dp)f", v), w)
        }

        var out = "=== consecutive days of daily weigh-ins + food logs ===\n"
        out += "  noise   conf>=0.5   conf>=0.8    conf@14d   conf@30d    sigma@30d\n"
        for noise in [0.3, 0.5, 0.7, 1.0, 1.5] {
            let c14 = confidence(records(days: 14, noise: noise))
            let c30 = confidence(records(days: 30, noise: noise))
            // confidence = sp^2/(sp^2+sm^2)  =>  sm = sp * sqrt((1-c)/c)
            let priorTDEE = engine.estimate(
                records: records(days: 30, intakeEvery: 99, noise: noise),
                windowDays: 30, prior: prior).tdeeKcal
            let sp = MetabolismEngine.priorRelativeError * priorTDEE
            let sm = c30 > 0 ? sp * ((1 - c30) / c30).squareRoot() : .infinity
            out += f(noise, 1, 5) + " kg"
                + pad(firstDay(noise: noise, reaching: 0.5).map { "\($0)d" } ?? ">30d", 11)
                + pad(firstDay(noise: noise, reaching: 0.8).map { "\($0)d" } ?? ">30d", 12)
                + f(c14, 2, 12) + f(c30, 2, 11)
                + f(sm, 0, 10) + " kcal\n"
        }
        // The other way to ask the question: by day n, how small a TDEE error is
        // even distinguishable from zero? Two standard errors is the usual bar.
        //
        // This is the honest floor. A 500 kcal/day error only shifts bodyweight
        // by 500·n/7700 kg, which at n=7 is 0.45 kg — less than one day's water
        // swing. No estimator recovers that; it is not in the data to recover.
        out += "\ndays   cumulative drift   smallest resolvable TDEE error (2 sigma)\n"
        out += "       from a 500 kcal/d error\n"
        for n in [7, 10, 14, 21, 28, 30] {
            let c = confidence(records(days: n, noise: 0.7))
            let priorTDEE = engine.estimate(
                records: records(days: n, intakeEvery: 99, noise: 0.7),
                windowDays: 30, prior: prior).tdeeKcal
            let sp = MetabolismEngine.priorRelativeError * priorTDEE
            let sm = c > 0 ? sp * ((1 - c) / c).squareRoot() : .infinity
            let drift = 500.0 * Double(n) / MetabolismEngine.kcalPerKg
            out += pad("\(n)d", 5) + f(drift, 2, 15) + " kg"
                + f(2 * sm, 0, 20) + " kcal/d\n"
        }
        // What the user would actually be shown as a range.
        out += "\ndays   TDEE   conf    +/- 1 sigma      95% interval\n"
        for n in [0, 7, 10, 14, 21, 30] {
            let recs = n == 0
                ? records(days: 30, weighInEvery: 99, intakeEvery: 99)
                : records(days: n, noise: 0.7)
            let e = engine.estimate(records: recs, windowDays: 30, prior: prior)
            let lo = e.interval95.lowerBound, hi = e.interval95.upperBound
            out += pad(n == 0 ? "none" : "\(n)d", 5)
                + f(e.tdeeKcal, 0, 7) + f(e.confidence, 2, 7)
                + f(e.standardErrorKcal, 0, 11) + " kcal"
                + pad("\(Int(lo))-\(Int(hi))", 17) + "\n"
        }
        // Where does the residual error actually live? Flat weight, steady
        // intake — the case where it feels like expenditure must equal intake.
        out += "\ndays   weight-trend term   food-log term   combined   log's share\n"
        for n in [10, 14, 21, 30, 60] {
            let recs = records(days: n, noise: 0.7)
            guard let b = engine.uncertaintyBreakdown(records: recs, windowDays: 30) else { continue }
            out += pad("\(n)d", 5) + f(b.weightTrendKcal, 0, 15) + " kcal"
                + f(b.intakeKcal, 0, 12) + " kcal"
                + f(b.combinedKcal, 0, 10) + f(b.intakeShare * 100, 0, 12) + "%\n"
        }
        // The same fortnight, if the food log were perfect.
        out += "\nwhat a flat fortnight can actually rule out:\n"
        if let b = engine.uncertaintyBreakdown(records: records(days: 14, noise: 0.7),
                                               windowDays: 30) {
            let kgPerWeek = b.weightTrendKcal * 7 / MetabolismEngine.kcalPerKg
            out += "  weight trend known to +/- " + f(kgPerWeek, 3, 1) + " kg/week"
                + "  =  +/- " + f(b.weightTrendKcal, 0, 1) + " kcal/day\n"
            out += "  a true " + f(b.weightTrendKcal, 0, 1)
                + " kcal/day imbalance moves weight only "
                + f(b.weightTrendKcal * 14 / MetabolismEngine.kcalPerKg, 2, 1)
                + " kg over the fortnight\n"
        }
        EngineComparisonTests.emit(out, to: "days-required.txt")

        // Typical scatter is 0.5-1.0 kg. Inside that band the measurement must
        // overtake the prior within a fortnight, and must not claim to have done
        // so within the first week.
        for noise in [0.5, 0.7, 1.0] {
            let crossover = firstDay(noise: noise, reaching: 0.5)
            #expect(crossover != nil)
            #expect(crossover! >= 8, "claimed reliability at day \(crossover!)")
            #expect(crossover! <= 14, "took \(crossover!) days to trust the data")
        }
    }

    /// Leverage beats count: readings spread across a fortnight pin a slope
    /// better than more readings crammed into a few days.
    @Test func spanMattersMoreThanCount() {
        let spread = confidence(records(days: 28, weighInEvery: 4, noise: 0.5))   // 7 weigh-ins
        let bunched = confidence(records(days: 8, weighInEvery: 1, noise: 0.5))   // 8 weigh-ins
        #expect(spread > bunched)
    }
}
