import Foundation

/// A clean-room re-derivation of the one calculation that matters most: how a
/// change in bodyweight becomes a change in the calorie goal.
///
/// Written from the energy balance directly rather than from `MetabolismEngine`,
/// so that running the two against the same inputs says something. Where they
/// disagree, one of them is wrong; where they agree, the answer is not an
/// artefact of a single implementation. Nothing calls this yet — it exists to be
/// compared against, and to be adopted only if the comparison earns it.
///
/// The physics is one line. Energy in minus energy out equals energy stored:
///
///     TDEE = meanIntake − (Δweight/day × kcalPerKg)
///
/// Everything else here is about not trusting that line when the inputs are too
/// thin to support it.
struct WeightEnergyModel: Sendable {

    /// kcal per kg of mixed tissue. Same constant as the existing engine — this
    /// is a physical value, not a modelling choice, so it is not re-litigated.
    static let kcalPerKg = 7700.0

    /// Fastest weekly change, as a fraction of bodyweight, treated as real
    /// tissue. Beyond this the reading is water, glycogen or a typo, and the
    /// energy inference has to be capped or a single bad weigh-in swamps it.
    static let maxWeeklyChangeFraction = 0.015

    /// Days of history required before the weight trend may influence the
    /// answer. Below this the target is the basal equation times activity, and
    /// the basis is reported as `bodySizeOnly` so the UI can say so.
    static let minHistoryDays = 7.0

    // MARK: - Inputs and outputs

    struct Day: Sendable {
        let date: Date
        let intakeKcal: Double?
        let weightKg: Double?
    }

    /// Which evidence the answer actually rests on. Carried out so callers can
    /// say *why* a number is what it is instead of presenting every estimate
    /// with equal authority.
    enum Basis: String, Sendable {
        /// Enough logged intake and weigh-ins to measure the balance directly.
        case measured
        /// Some of both, but not enough to stand alone.
        case blended
        /// No usable intake. The weight trend cannot be converted to energy at
        /// all, so this is a body-size estimate and nothing more.
        case bodySizeOnly
    }

    struct Result: Sendable {
        var tdeeKcal: Double
        var calorieGoalKcal: Double
        /// What the weigh-ins actually did, unclamped — for display.
        var observedSlopeKgPerWeek: Double
        /// What was allowed into the energy inference, after capping.
        var appliedSlopeKgPerWeek: Double
        var confidence: Double
        var basis: Basis
        /// Weight the answer is anchored to.
        var referenceWeightKg: Double
        /// Set when the goal was moved by a safety rail rather than by the
        /// arithmetic, so a caller can explain a target that looks off.
        var limitedBy: String?
    }

    // MARK: - Entry point

    /// - Parameters:
    ///   - basalKcal: resting rate for `referenceWeight`, supplied by the caller
    ///     so this stays a pure function of energy rather than of anthropometry.
    ///   - activityFactor: multiplier used only when intake cannot carry the
    ///     estimate.
    static func evaluate(days: [Day],
                         windowDays: Int,
                         goal: FitnessGoal,
                         basal: (Double) -> Double,
                         activityFactor: Double,
                         asOf: Date = .now) -> Result {

        let window = daysInWindow(days, windowDays: windowDays, asOf: asOf)
            .sorted { $0.date < $1.date }
        let weights = dailyWeights(window)
        let intakes = window.compactMap(\.intakeKcal)

        // Anchor on the most recent weigh-in rather than a smoothed value.
        //
        // Deliberately different from the existing engine, which anchors basal
        // on a 10-day EWMA. Smoothing is right for the *trend* — one reading
        // carries water noise — but it is wrong for "how big is this person
        // now", because it means a real, sustained change takes a fortnight to
        // reach the calorie goal, and a corrected weigh-in only moves the goal
        // a fraction of the way. That lag is indistinguishable from a bug.
        let reference = weights.last?.kg ?? 75
        let basalKcal = basal(reference)

        let observedSlope = robustSlopePerDay(weights)
        let cap = reference * maxWeeklyChangeFraction / 7
        let appliedSlope = min(max(observedSlope, -cap), cap)

        let confidence = confidence(window: window, weighInDays: weights.count,
                                    windowDays: windowDays)
        let bodySizeTDEE = basalKcal * activityFactor

        let historyDays = window.first.map { asOf.timeIntervalSince($0.date) / 86_400 } ?? 0

        let tdee: Double
        let basis: Basis
        if historyDays < minHistoryDays || intakes.isEmpty || weights.count < 2 {
            // No intake, or nothing to take a slope from: the balance equation
            // has no left-hand side. Say so rather than dressing a body-size
            // guess up as a measurement.
            tdee = bodySizeTDEE
            basis = .bodySizeOnly
        } else {
            let measured = mean(intakes) - appliedSlope * kcalPerKg
            tdee = confidence * measured + (1 - confidence) * bodySizeTDEE
            basis = confidence >= 0.75 ? .measured : .blended
        }

        let goalResult = calorieGoal(tdee: tdee, basalKcal: basalKcal,
                                     goal: goal, bodyweightKg: reference)

        return Result(tdeeKcal: tdee.rounded(),
                      calorieGoalKcal: goalResult.kcal.rounded(),
                      observedSlopeKgPerWeek: observedSlope * 7,
                      appliedSlopeKgPerWeek: appliedSlope * 7,
                      confidence: confidence,
                      basis: basis,
                      referenceWeightKg: reference,
                      limitedBy: goalResult.limitedBy)
    }

    // MARK: - Goal

    /// TDEE to a daily target, with the rails that stop a wrong TDEE turning
    /// into a dangerous prescription.
    static func calorieGoal(tdee: Double, basalKcal: Double,
                            goal: FitnessGoal,
                            bodyweightKg: Double) -> (kcal: Double, limitedBy: String?) {
        let requested = tdee * (1 + goal.calorieOffset)

        // Rate rails: at most 1%/wk down, 0.5%/wk up, expressed as energy.
        let maxDeficit = bodyweightKg * 0.01 * kcalPerKg / 7
        let maxSurplus = bodyweightKg * 0.005 * kcalPerKg / 7

        // Never prescribe under basal. This is a floor, not a preference: below
        // it, lean-mass loss and adaptive suppression stop being avoidable.
        let floor = max(tdee - maxDeficit, basalKcal)
        let ceiling = tdee + maxSurplus

        // A depressed TDEE can push the floor above the ceiling. Basal wins, and
        // the caller is told, because a target that ignores the goal entirely
        // needs explaining.
        guard floor <= ceiling else { return (max(floor, basalKcal), "basal floor") }
        if requested < floor { return (floor, floor == basalKcal ? "basal floor" : "deficit rate") }
        if requested > ceiling { return (ceiling, "surplus rate") }
        return (requested, nil)
    }

    // MARK: - Series

    private struct WeighIn { let day: Double; let kg: Double }

    private static func daysInWindow(_ days: [Day], windowDays: Int, asOf: Date) -> [Day] {
        let cal = Calendar(identifier: .gregorian)
        guard let start = cal.date(byAdding: .day, value: -windowDays, to: asOf) else { return days }
        return days.filter { $0.date >= start && $0.date <= asOf }
    }

    /// One weight per calendar day, averaging repeats. Averaging rather than
    /// last-wins: two weigh-ins on one day are two samples of the same quantity,
    /// and picking one by fetch order makes the answer depend on storage.
    private static func dailyWeights(_ window: [Day]) -> [WeighIn] {
        let cal = Calendar(identifier: .gregorian)
        var byDay: [Date: [Double]] = [:]
        for d in window {
            guard let kg = d.weightKg else { continue }
            byDay[cal.startOfDay(for: d.date), default: []].append(kg)
        }
        guard let origin = byDay.keys.min() else { return [] }
        return byDay.keys.sorted().map { day in
            let all = byDay[day]!
            return WeighIn(day: day.timeIntervalSince(origin) / 86_400,
                           kg: all.reduce(0, +) / Double(all.count))
        }
    }

    /// Theil–Sen: the median of all pairwise slopes.
    ///
    /// Chosen over least squares because its breakdown point is 29% — roughly a
    /// third of the weigh-ins can be nonsense before the answer is. Least
    /// squares has a breakdown point of zero: one bad number moves it without
    /// limit, and one bad number is exactly the failure mode here.
    static func robustSlopePerDay(_ points: [(day: Double, kg: Double)]) -> Double {
        robustSlopePerDay(points.map { WeighIn(day: $0.day, kg: $0.kg) })
    }

    private static func robustSlopePerDay(_ points: [WeighIn]) -> Double {
        guard points.count >= 2 else { return 0 }
        var slopes: [Double] = []
        slopes.reserveCapacity(points.count * (points.count - 1) / 2)
        for i in points.indices {
            for j in points.indices where j > i && points[j].day != points[i].day {
                slopes.append((points[j].kg - points[i].kg) / (points[j].day - points[i].day))
            }
        }
        return median(slopes)
    }

    // MARK: - Confidence

    /// How much of the answer the measurement has earned, in [0, 1].
    ///
    /// Three independent ways the evidence can be thin, multiplied because any
    /// one of them alone is enough to make the balance untrustworthy:
    /// days with intake, days with a weigh-in, and whether the window is long
    /// enough for a slope to mean anything.
    private static func confidence(window: [Day], weighInDays: Int, windowDays: Int) -> Double {
        guard windowDays > 0 else { return 0 }
        let intakeDays = window.filter { $0.intakeKcal != nil }.count
        let intakeCoverage = min(1, Double(intakeDays) / Double(windowDays))
        // A weigh-in every third day is enough to place a trend.
        let weighInCoverage = min(1, Double(weighInDays) / (Double(windowDays) / 3))
        let windowMaturity = min(1, Double(windowDays) / 14)
        return (intakeCoverage * weighInCoverage * windowMaturity).clamped(to: 0...1)
    }

    // MARK: - Small helpers

    private static func mean(_ xs: [Double]) -> Double {
        xs.isEmpty ? 0 : xs.reduce(0, +) / Double(xs.count)
    }

    private static func median(_ xs: [Double]) -> Double {
        guard !xs.isEmpty else { return 0 }
        let s = xs.sorted()
        let mid = s.count / 2
        return s.count.isMultiple(of: 2) ? (s[mid - 1] + s[mid]) / 2 : s[mid]
    }
}
