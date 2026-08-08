import Foundation

/// Body-recomposition goal. Drives target-calorie offset and default protein.
enum FitnessGoal: String, Codable, CaseIterable, Sendable {
    case fatLoss, maintenance, muscleGain, recomposition

    /// Fraction applied to TDEE to get the calorie target.
    var calorieOffset: Double {
        switch self {
        case .fatLoss: return -0.20
        case .recomposition: return -0.10
        case .maintenance: return 0
        case .muscleGain: return 0.10
        }
    }

    /// Protein target in g per kg of the chosen basis.
    ///
    /// The literature's 1.8–2.2 g/kg figures are referenced to *bodyweight*.
    /// Applying them to lean mass under-prescribes by roughly the body-fat
    /// fraction (82 kg at 65 kg LBM → 130 g instead of 164 g), so the lean-mass
    /// basis carries its own, higher values (Helms et al. 2014 give 2.3–3.1
    /// g/kg LBM for lifters in a deficit; the upper end is for very lean
    /// contest prep, so this stays conservative).
    func defaultProtein(perLeanMass: Bool) -> Double {
        switch (self, perLeanMass) {
        case (.fatLoss, false), (.recomposition, false): return 2.0
        case (.fatLoss, true), (.recomposition, true): return 2.4
        case (.maintenance, false), (.muscleGain, false): return 1.8
        case (.maintenance, true), (.muscleGain, true): return 2.2
        }
    }
}

enum BiologicalSex: String, Codable, Sendable { case male, female, other }

/// Coarse activity prior used only to seed the BMR-based estimate before enough
/// trend data exists. Once measured TDEE has confidence this is discarded.
enum ActivityBaseline: String, Codable, CaseIterable, Sendable {
    case sedentary, light, moderate, active, athlete

    var factor: Double {
        switch self {
        case .sedentary: return 1.2
        case .light: return 1.375
        case .moderate: return 1.55
        case .active: return 1.725
        case .athlete: return 1.9
        }
    }
}

/// One day of intake + bodyweight. Either field may be missing.
struct DailyRecord: Sendable {
    let date: Date
    let intakeKcal: Double?
    let weightKg: Double?
}

struct TDEEEstimate: Sendable {
    let tdeeKcal: Double
    let confidence: Double          // 0…1
    let trendSlopeKgPerWeek: Double
    let avgIntakeKcal: Double
    let smoothedWeightKg: Double
    let windowDays: Int
    /// Basal rate behind this estimate — Katch-McArdle when lean mass was known,
    /// Mifflin-St Jeor otherwise. Carried so `calorieTarget` can refuse to
    /// prescribe below it.
    var basalKcal: Double = 0

    /// Standard error of `tdeeKcal`, in kcal/day.
    ///
    /// Falls out of the same inverse-variance blend that produces `confidence`.
    /// Combining two estimates is more precise than either alone, so:
    ///
    ///     1/σ_post² = 1/σ_prior² + 1/σ_measured²   ⟹   σ_post = σ_prior·√(1 − c)
    ///
    /// At c = 0 this is the prior's own spread, which is the right answer: a
    /// day-one target is a population formula and carries a population formula's
    /// error. At c = 1 it would be zero, which is why
    /// `intakeSystematicErrorFraction` exists to stop c ever reaching 1.
    var standardErrorKcal: Double = 0

    /// The interval `tdeeKcal` actually lives in, at ~95%.
    var interval95: ClosedRange<Double> {
        let half = 1.96 * standardErrorKcal
        return (tdeeKcal - half)...(tdeeKcal + half)
    }
}

/// Adaptive TDEE from the relationship between logged intake and the smoothed
/// bodyweight trend. Pure and Sendable — no I/O. See docs/ALGORITHMS.md §1.
struct MetabolismEngine: Sendable {

    /// kcal per kg of body-mass change (standard mixed-tissue value).
    static let kcalPerKg = 7700.0

    /// Fastest weekly weight change, as a fraction of bodyweight, that is treated
    /// as real tissue when inferring TDEE.
    ///
    /// The inference assumes a weight change *is* stored or burned energy, so a
    /// wrong number doesn't produce a slightly wrong answer — it produces an
    /// absurd one. Measured on this engine: a single mistyped weigh-in of 89 kg
    /// instead of 80 gives a +9 kg/week slope and a TDEE of **452 kcal**.
    ///
    /// 1.5% a week is well clear of any real cut or bulk — a hard cut runs near
    /// 1%, and beyond that you are measuring water, glycogen or a typo. The
    /// *reported* trend is left untouched so the user still sees what they
    /// actually logged; only the energy inference is clamped.
    static let maxPlausibleWeeklyChangeFraction = 0.015

    // MARK: - When the measurement is allowed to count
    //
    // Three hard bounds, then a continuous precision test. The bounds exist
    // because below them the precision test cannot even be computed; everything
    // above them is decided by how much the data actually pins TDEE down.

    /// Two points still place a line; they just cannot say how noisy it is.
    /// That is what `assumedDailyWeightSD` is for, so the floor here is only the
    /// point below which there is no line at all.
    static let minWeighInsForInference = 2

    /// Day-to-day bodyweight scatter, in kg, before the user's own weigh-ins
    /// have shown otherwise. Water, glycogen and gut content move a person this
    /// much overnight regardless of energy balance.
    ///
    /// Used as a prior rather than an assumption: it stands alone at two
    /// weigh-ins, and is progressively displaced by the observed scatter as the
    /// series grows. This is what stops three nearly-collinear readings from
    /// reporting near-zero error and claiming certainty they haven't earned.
    static let assumedDailyWeightSD = 0.7

    /// Weight of that prior, in pseudo-observations. At 3, the observed scatter
    /// is worth more than the prior once there are ~5 weigh-ins.
    static let weightSDPriorStrength = 3.0

    /// Shortest span the weigh-ins must cover. Leverage, not count: five
    /// weigh-ins inside three days pin a slope far worse than five across a
    /// fortnight, because the slope's precision goes as the spread of the
    /// *dates*, not the number of readings.
    static let minWeighInSpanDays = 7.0

    /// Below this there is no usable intake average to difference the weight
    /// trend against.
    static let minIntakeDaysForInference = 3

    // Food-log error, split by whether repetition can wash it out.
    //
    // This app is built for people who weigh their food and train seriously, so
    // it does not assume the population-level under-reporting the literature
    // finds in free-living adults (commonly 10–30%). It assumes ~90–95% accuracy
    // and, importantly, that the misses go both ways.
    //
    // That distinction is worth more than the headline figure. Random error
    // averages out — over n logged days the error on the *mean* falls as 1/√n —
    // whereas systematic error does not, no matter how long the streak. Folding
    // both into one constant, as this used to, quietly asserted that a careful
    // logger can never do better than a sloppy one.

    /// Error that survives averaging: database entries a little off, cooking
    /// losses, the same oil under-counted every time. Small for a weigher, but
    /// never zero — which is what keeps confidence short of 1.
    static let intakeSystematicErrorFraction = 0.025

    /// Day-to-day random error: portions estimated by eye, an unlogged coffee,
    /// a restaurant meal. Averages down across logged days.
    static let intakeRandomErrorFraction = 0.07

    /// Day-to-day swing in intake, as a fraction of the mean, used as a floor
    /// when the logged days don't reveal it themselves.
    ///
    /// Without it, a run of identically-logged days implies the *unlogged* days
    /// are known exactly, and skipping food logging costs nothing at all. Even
    /// consistent eaters move ~20% between a training day and a rest day.
    static let intakeDayVariationFraction = 0.20

    /// Relative error of the prior. Mifflin-St Jeor carries roughly ±10% on
    /// basal, and the activity multiplier is a five-way bucket worth about
    /// ±15%; in quadrature, ~18%.
    static let priorRelativeError = 0.18

    /// Standard error of the measured TDEE in kcal/day, or `nil` when the bounds
    /// above are not met.
    ///
    ///     σ_measured² = (kcalPerKg · σ_slope)² + σ_intake²
    ///     σ_slope     = σ_residual / √Σ(xᵢ - x̄)²
    ///
    /// The `√Σ(xᵢ - x̄)²` term is what makes this robust to skipped days: a gap
    /// removes one point's contribution to the spread rather than invalidating
    /// the series, so confidence dips and recovers instead of resetting.
    /// Where the uncertainty in a measured TDEE comes from.
    ///
    /// Worth surfacing rather than hiding: the two terms behave completely
    /// differently. The weight term shrinks as history accumulates; the intake
    /// term does not shrink at all, because it is bias rather than noise —
    /// logging the same wrong number for a month gives a very precise estimate
    /// of a wrong number.
    struct UncertaintyBreakdown: Sendable {
        /// From not knowing the weight trend exactly, × 7700 kcal/kg.
        let weightTrendKcal: Double
        /// From not knowing what was actually eaten.
        let intakeKcal: Double
        var combinedKcal: Double {
            (weightTrendKcal * weightTrendKcal + intakeKcal * intakeKcal).squareRoot()
        }
        /// Share of the variance owed to the food log, 0…1.
        var intakeShare: Double {
            let total = combinedKcal * combinedKcal
            return total > 0 ? (intakeKcal * intakeKcal) / total : 0
        }
    }

    /// `UncertaintyBreakdown` for a set of records, or nil below the bounds.
    func uncertaintyBreakdown(records: [DailyRecord], windowDays: Int,
                              asOf: Date = Date()) -> UncertaintyBreakdown? {
        let cal = Calendar(identifier: .gregorian)
        let start = cal.date(byAdding: .day, value: -windowDays, to: asOf) ?? asOf
        let window = records
            .filter { $0.date >= start && $0.date <= asOf }
            .sorted { $0.date < $1.date }
        return measurementStandardError(daily: dailyWeightSeries(window),
                                        intakes: window.compactMap(\.intakeKcal),
                                        windowDays: windowDays,
                                        avgIntake: imputedAverageIntake(window, asOf: asOf))
    }

    private func measurementStandardError(daily: [Point], intakes: [Double],
                                          windowDays: Int,
                                          avgIntake: Double) -> UncertaintyBreakdown? {
        guard daily.count >= Self.minWeighInsForInference,
              intakes.count >= Self.minIntakeDaysForInference,
              let first = daily.first?.day, let last = daily.last?.day,
              last - first >= Self.minWeighInSpanDays
        else { return nil }

        // Scatter of the weigh-ins about their own trend line, shrunk toward the
        // physiological prior so that a short or unluckily tidy series cannot
        // claim more precision than it has.
        let slope = theilSenSlopePerDay(daily)
        let intercept = median(daily.map { $0.value - slope * $0.day })
        let residuals = daily.map { $0.value - (intercept + slope * $0.day) }
        let dof = Double(max(0, daily.count - 2))
        let observedVar = dof > 0 ? residuals.reduce(0) { $0 + $1 * $1 } / dof : 0
        let priorVar = Self.assumedDailyWeightSD * Self.assumedDailyWeightSD
        let pooledVar = (dof * observedVar + Self.weightSDPriorStrength * priorVar)
            / (dof + Self.weightSDPriorStrength)
        let residualSD = pooledVar.squareRoot()

        let meanDay = daily.reduce(0) { $0 + $1.day } / Double(daily.count)
        let sxx = daily.reduce(0) { $0 + ($1.day - meanDay) * ($1.day - meanDay) }
        guard sxx > 0 else { return nil }
        let weightTermSD = (residualSD / sxx.squareRoot()) * Self.kcalPerKg

        // Intake: sampling error over the days that were not logged, plus the
        // self-report error that never goes away.
        let k = Double(intakes.count)
        let mean = intakes.reduce(0, +) / k
        let observedIntakeVar = k > 1
            ? intakes.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / (k - 1)
            : 0
        let floorIntakeVar = (Self.intakeDayVariationFraction * mean)
            * (Self.intakeDayVariationFraction * mean)
        let variance = max(observedIntakeVar, floorIntakeVar)
        let unlogged = max(0, Double(windowDays) - k)
        let days = Double(max(windowDays, 1))
        let imputationVar = (unlogged * unlogged * (variance / k) + unlogged * variance)
            / (days * days)
        // Systematic error passes straight through to the mean; random error is
        // divided by the number of days that were actually logged.
        let systematic = Self.intakeSystematicErrorFraction * avgIntake
        let random = Self.intakeRandomErrorFraction * avgIntake
        let reportVar = systematic * systematic + (random * random) / k
        let intakeSD = (imputationVar + reportVar).squareRoot()

        return UncertaintyBreakdown(weightTrendKcal: weightTermSD, intakeKcal: intakeSD)
    }

    private func median(_ xs: [Double]) -> Double {
        guard !xs.isEmpty else { return 0 }
        let s = xs.sorted()
        let mid = s.count / 2
        return s.count.isMultiple(of: 2) ? (s[mid - 1] + s[mid]) / 2 : s[mid]
    }

    struct Prior: Sendable {
        let sex: BiologicalSex
        let ageYears: Double
        let heightCm: Double
        let activity: ActivityBaseline
        /// Mean daily active energy (HealthKit) over the window. When present,
        /// the prior becomes passive BMR + measured activity (grossed up for
        /// TEF) and the guessed activity factor is ignored.
        var avgActiveEnergyKcal: Double?
        /// Lean mass, when known. Switches the basal estimate from
        /// Mifflin-St Jeor to Katch-McArdle — see `bmr(_:weightKg:)`.
        var leanMassKg: Double?

        init(sex: BiologicalSex, ageYears: Double, heightCm: Double,
             activity: ActivityBaseline, avgActiveEnergyKcal: Double? = nil,
             leanMassKg: Double? = nil) {
            self.sex = sex
            self.ageYears = ageYears
            self.heightCm = heightCm
            self.activity = activity
            self.avgActiveEnergyKcal = avgActiveEnergyKcal
            self.leanMassKg = leanMassKg
        }
    }

    /// Headline estimate over `windowDays`, blended with a BMR prior by confidence.
    func estimate(records: [DailyRecord],
                  windowDays: Int,
                  prior: Prior,
                  asOf: Date = Date()) -> TDEEEstimate {

        let cal = Calendar(identifier: .gregorian)
        let start = cal.date(byAdding: .day, value: -windowDays, to: asOf) ?? asOf
        let window = records
            .filter { $0.date >= start && $0.date <= asOf }
            .sorted { $0.date < $1.date }

        return estimatePrepared(records: window, windowDays: windowDays,
                                prior: prior, asOf: asOf)
    }

    /// The same calculation as `estimate`, for callers that already maintain a
    /// sorted trailing window. History charts advance that window one day at a
    /// time; filtering and sorting the full year for every point was pure
    /// duplicate work. Kept internal so ordinary callers cannot accidentally
    /// pass records outside the requested window.
    func estimatePrepared(records window: [DailyRecord],
                          windowDays: Int,
                          prior: Prior,
                          asOf: Date) -> TDEEEstimate {

        // Slope from RAW daily means via Theil–Sen: smoothing first (EWMA→OLS)
        // lags the trend and biased TDEE ~11% low at 30d, ~30% at 14d in
        // validation. Theil–Sen is unbiased on clean trends and immune to
        // single-day water-weight spikes anywhere in the window.
        let daily = dailyWeightSeries(window)
        let smoothed = smoothedWeightSeries(daily)
        let slopePerDay = theilSenSlopePerDay(daily)
        let slopePerWeek = slopePerDay * 7

        let intakes = window.compactMap(\.intakeKcal)
        // Averaged over every day in the window, unlogged days imputed from the
        // intake trend — the weight slope it's differenced against covers all of
        // them, so the intake side has to as well.
        let avgIntake = imputedAverageIntake(window, asOf: asOf)

        // Clamped before it becomes energy: see maxPlausibleWeeklyChangeFraction.
        let referenceWeight = smoothed.last?.value ?? daily.last?.value ?? 75
        let maxPerDay = referenceWeight * Self.maxPlausibleWeeklyChangeFraction / 7
        let inferenceSlope = slopePerDay.clamped(to: -maxPerDay...maxPerDay)
        let rawTDEE = avgIntake - inferenceSlope * Self.kcalPerKg

        // Prior: passive BMR + measured active energy when HealthKit has it
        // (÷0.9 grosses up for the ~10% thermic effect of food); otherwise the
        // coarse activity-factor guess.
        let passiveBMR = bmr(prior, weightKg: smoothed.last?.value ?? 75)
        let priorTDEE: Double
        if let active = prior.avgActiveEnergyKcal {
            priorTDEE = (passiveBMR + active) / 0.9
        } else {
            priorTDEE = passiveBMR * prior.activity.factor
        }

        // Confidence is now derived, not assembled from coverage heuristics.
        //
        // The measurement and the prior are two estimates of the same quantity
        // with different precisions, so they combine by inverse variance:
        //
        //     confidence = σ_prior² / (σ_prior² + σ_measured²)
        //
        // which is the weight a precision-weighted mean gives the measurement.
        // Everything the old heuristic was groping at falls out of σ_measured:
        // few weigh-ins, a short span, noisy scales and sparse food logging all
        // inflate it, and skipping a day costs exactly the leverage that day
        // would have contributed — no cliff, no special case.
        let measuredSD = measurementStandardError(daily: daily, intakes: intakes,
                                                  windowDays: windowDays,
                                                  avgIntake: avgIntake)
        let priorSD = Self.priorRelativeError * priorTDEE
        let confidence: Double = {
            guard let sd = measuredSD?.combinedKcal, sd > 0, priorSD > 0 else { return 0 }
            return (priorSD * priorSD / (priorSD * priorSD + sd * sd)).clamped(to: 0...1)
        }()

        let blended = intakes.isEmpty
            ? priorTDEE
            : confidence * rawTDEE + (1 - confidence) * priorTDEE

        return TDEEEstimate(
            tdeeKcal: blended.rounded(),
            confidence: confidence,
            trendSlopeKgPerWeek: slopePerWeek,
            avgIntakeKcal: avgIntake.rounded(),
            smoothedWeightKg: smoothed.last?.value ?? 0,
            windowDays: windowDays,
            basalKcal: passiveBMR.rounded(),
            standardErrorKcal: (priorSD * (1 - confidence).squareRoot()).rounded()
        )
    }

    /// Calorie target for a goal, guard-railed so weekly weight change stays in a
    /// muscle-retention / lean-gain safe band relative to bodyweight, and never
    /// below basal metabolic rate.
    func calorieTarget(tdee: TDEEEstimate, goal: FitnessGoal, bodyweightKg: Double) -> Double {
        let raw = tdee.tdeeKcal * (1 + goal.calorieOffset)

        let maxLossKcal = bodyweightKg * 0.01 * Self.kcalPerKg / 7   // 1%/wk
        let maxGainKcal = bodyweightKg * 0.005 * Self.kcalPerKg / 7  // 0.5%/wk

        // Relative guardrails alone can prescribe below BMR for a small or
        // low-TDEE user: a 1%/wk deficit is a fixed fraction of bodyweight, not
        // of metabolic rate. Eating under basal is the point at which lean-mass
        // loss and adaptive suppression stop being avoidable, so it's a floor,
        // not a preference. Falls back to a conservative absolute minimum when
        // BMR is unknown (estimates built from persisted records pre-migration).
        let basalFloor = tdee.basalKcal > 0 ? tdee.basalKcal : 1200
        let relativeFloor = tdee.tdeeKcal - maxLossKcal
        let floor = max(relativeFloor, basalFloor)
        let ceiling = tdee.tdeeKcal + maxGainKcal

        // A very low TDEE can put the floor above the ceiling; the floor wins.
        guard floor <= ceiling else { return floor.rounded() }
        return raw.clamped(to: floor...ceiling).rounded()
    }

    // MARK: - Internals

    private struct Point: Sendable { let day: Double; let value: Double }

    /// Mean daily intake across **every** day in the window, with unlogged days
    /// imputed from the intake trend of the days that were logged.
    ///
    /// All days are treated as exchangeable — no day-of-week structure is assumed
    /// or looked for. Under that assumption the mean of logged days is already an
    /// unbiased estimate of the window mean, and mean-imputing gaps would give an
    /// identical answer. What imputation adds is *time*: when intake drifts across
    /// the window and the gaps cluster in time — the first week unlogged, say —
    /// the flat average of logged days describes the wrong part of the window,
    /// while the weight trend it's differenced against covers all of it.
    ///
    /// Theil–Sen again, for the same reason as the weight slope: a couple of
    /// outlier days (a blowout, a fast) shouldn't tilt the fitted line.
    ///
    /// **The span is calendar days, not days that happen to hold a record.** It
    /// used to average over every day carrying *any* record — which included
    /// weigh-in days — so the number of gaps the trend was projected across was
    /// set partly by how often the user stepped on the scale. Measured on this
    /// engine with intake declining over a month and food logged for the first
    /// fortnight: weighing daily gave 2590 kcal, weighing weekly 2644, a 61 kcal
    /// difference in TDEE from identical eating. Weight logging was deciding the
    /// food average.
    ///
    /// It runs from the first record to the end of the window rather than across
    /// the nominal `windowDays`, so a user two weeks into using the app does not
    /// have a fortnight of intake invented for them from before they arrived.
    /// The denominator still varies with how much history exists — but on when
    /// they started, which is real, rather than on a weighing habit, which is
    /// not.
    private func imputedAverageIntake(_ window: [DailyRecord], asOf: Date) -> Double {
        let cal = Calendar(identifier: .gregorian)
        var byDay: [Date: Double] = [:]
        for r in window {
            if let kcal = r.intakeKcal { byDay[cal.startOfDay(for: r.date)] = kcal }
        }
        let observed = Array(byDay.values)
        guard !observed.isEmpty else { return 0 }

        let flatMean = observed.reduce(0, +) / Double(observed.count)
        // Under three logged days a trend is noise; fall back to the flat mean.
        guard byDay.count >= 3,
              let origin = window.map({ cal.startOfDay(for: $0.date) }).min()
        else { return flatMean }

        let lastDay = cal.startOfDay(for: asOf)
        let spanDays = Int((lastDay.timeIntervalSince(origin) / 86_400).rounded()) + 1
        guard spanDays >= byDay.count else { return flatMean }

        let points = byDay
            .map { Point(day: $0.key.timeIntervalSince(origin) / 86_400, value: $0.value) }
            .sorted { $0.day < $1.day }
        let slope = theilSenSlopePerDay(points)
        guard slope != 0 else { return flatMean }

        // Theil–Sen intercept: median residual once the slope is removed.
        var residuals = points.map { $0.value - slope * $0.day }
        residuals.sort()
        let mid = residuals.count / 2
        let intercept = residuals.count.isMultiple(of: 2)
            ? (residuals[mid - 1] + residuals[mid]) / 2
            : residuals[mid]

        // Only project a trend that stands clear of day-to-day noise. Fitting
        // noise and extrapolating it across an unlogged stretch is worse than
        // not trying: in simulation an unguarded fit turned a 14 kcal error into
        // 26 on genuinely flat intake. Requiring the drift across the window to
        // exceed one residual SD keeps ~90% of the benefit on real trends
        // (71 → 25 kcal) while costing ~6 kcal when there is no trend.
        let spread = points.map { $0.value - (intercept + slope * $0.day) }
        let residualMean = spread.reduce(0, +) / Double(spread.count)
        let residualSD = (spread.reduce(0) { $0 + ($1 - residualMean) * ($1 - residualMean) }
                          / Double(max(1, spread.count - 1))).squareRoot()
        let drift = abs(slope) * ((points.last?.day ?? 0) - (points.first?.day ?? 0))
        guard drift >= residualSD else { return flatMean }

        // Extrapolating a trend across a long unlogged stretch can still run
        // away, so imputed values are held inside the range actually observed.
        let low = observed.min() ?? flatMean
        let high = observed.max() ?? flatMean

        var total = 0.0
        for offset in 0..<spanDays {
            guard let day = cal.date(byAdding: .day, value: offset, to: origin) else { continue }
            if let logged = byDay[day] {
                total += logged
            } else {
                total += (intercept + slope * Double(offset)).clamped(to: low...high)
            }
        }
        return total / Double(spanDays)
    }

    /// Raw daily weights — the lowest reading of each day. See `DailyWeight`.
    private func dailyWeightSeries(_ window: [DailyRecord]) -> [Point] {
        let byDay = DailyWeight.byDay(window, date: \.date, weightKg: \.weightKg,
                                      calendar: Calendar(identifier: .gregorian))
        guard let origin = byDay.keys.min() else { return [] }
        return byDay.keys.sorted().map { day in
            Point(day: day.timeIntervalSince(origin) / 86_400, value: byDay[day]!)
        }
    }

    /// EWMA over the daily series — display trend only, never fed to the slope.
    private func smoothedWeightSeries(_ daily: [Point]) -> [Point] {
        let alpha = 2.0 / (10 + 1)   // N≈10-day responsiveness
        var trend: Double?
        return daily.map { p in
            trend = trend.map { alpha * p.value + (1 - alpha) * $0 } ?? p.value
            return Point(day: p.day, value: trend!)
        }
    }

    /// Theil–Sen slope (kg/day): median of all pairwise slopes. O(n²) pairs but
    /// n ≤ 30, so at most 435 — negligible.
    private func theilSenSlopePerDay(_ points: [Point]) -> Double {
        guard points.count >= 2 else { return 0 }
        var slopes: [Double] = []
        for i in 0..<points.count {
            for j in (i + 1)..<points.count where points[j].day != points[i].day {
                slopes.append((points[j].value - points[i].value) / (points[j].day - points[i].day))
            }
        }
        guard !slopes.isEmpty else { return 0 }
        slopes.sort()
        let mid = slopes.count / 2
        return slopes.count.isMultiple(of: 2)
            ? (slopes[mid - 1] + slopes[mid]) / 2
            : slopes[mid]
    }

    /// Basal rate, by whichever equation the available data supports.
    ///
    /// **Katch-McArdle when lean mass is known** — `370 + 21.6 x LBM`. It drops
    /// sex, age and height entirely because lean mass already carries what those
    /// were proxying for, which is why it beats Mifflin *when the body-fat figure
    /// is real*: a DEXA scan (+/-1.5% body fat) puts basal within about +/-27
    /// kcal, against Mifflin's typical +/-180.
    ///
    /// **Mifflin-St Jeor otherwise.** Deliberately not a self-estimated body-fat
    /// range: 5 points of body-fat error moves this by ~89 kcal, so a guessed
    /// bracket is no better than Mifflin — and people systematically underestimate
    /// their own body fat, which would inflate lean mass, inflate basal, and raise
    /// the calorie floor enough to block legitimate deficits. Unbiased noise beats
    /// biased noise.
    private func bmr(_ p: Prior, weightKg: Double) -> Double {
        // Strict on both bounds, matching `BodyComposition` and
        // `SyncCoordinator.upsertComposition`. A lean mass equal to bodyweight
        // is 0% body fat, and taking it would inflate this by ~318 kcal at
        // 80 kg — straight into the calorie floor below.
        if let lean = p.leanMassKg, lean > 0, lean < weightKg {
            return 370 + 21.6 * lean
        }
        let base = 10 * weightKg + 6.25 * p.heightCm - 5 * p.ageYears
        switch p.sex {
        case .male: return base + 5
        case .female: return base - 161
        case .other: return base - 78   // midpoint
        }
    }
}

extension Comparable {
    func clamped(to r: ClosedRange<Self>) -> Self {
        min(max(self, r.lowerBound), r.upperBound)
    }
}
