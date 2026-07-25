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
    /// Mifflin-St Jeor basal rate for the profile behind this estimate. Carried
    /// so `calorieTarget` can refuse to prescribe below it.
    var basalKcal: Double = 0
}

/// Adaptive TDEE from the relationship between logged intake and the smoothed
/// bodyweight trend. Pure and Sendable — no I/O. See docs/ALGORITHMS.md §1.
struct MetabolismEngine: Sendable {

    /// kcal per kg of body-mass change (standard mixed-tissue value).
    static let kcalPerKg = 7700.0

    struct Prior: Sendable {
        let sex: BiologicalSex
        let ageYears: Double
        let heightCm: Double
        let activity: ActivityBaseline
        /// Mean daily active energy (HealthKit) over the window. When present,
        /// the prior becomes passive BMR + measured activity (grossed up for
        /// TEF) and the guessed activity factor is ignored.
        var avgActiveEnergyKcal: Double?

        init(sex: BiologicalSex, ageYears: Double, heightCm: Double,
             activity: ActivityBaseline, avgActiveEnergyKcal: Double? = nil) {
            self.sex = sex
            self.ageYears = ageYears
            self.heightCm = heightCm
            self.activity = activity
            self.avgActiveEnergyKcal = avgActiveEnergyKcal
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
        let avgIntake = imputedAverageIntake(window)

        let rawTDEE = avgIntake - slopePerDay * Self.kcalPerKg

        let coverage = Double(intakes.count) / Double(max(windowDays, 1))
        let weighIns = smoothed.count
        let dataMaturity = min(1, Double(windowDays) / 14)
        let weighInDensity = min(1, Double(weighIns) / (Double(windowDays) / 3))
        // Coverage still discounts: imputed days are inference, not measurement,
        // and a window that is mostly imputed deserves less weight against the
        // prior — even though the imputation itself is unbiased.
        let confidence = (coverage * dataMaturity * weighInDensity)
            .clamped(to: 0...1)

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
            basalKcal: passiveBMR.rounded()
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
    private func imputedAverageIntake(_ window: [DailyRecord]) -> Double {
        let cal = Calendar(identifier: .gregorian)
        var byDay: [Date: Double] = [:]
        var allDays: Set<Date> = []
        for r in window {
            let day = cal.startOfDay(for: r.date)
            allDays.insert(day)
            if let kcal = r.intakeKcal { byDay[day] = kcal }
        }
        let observed = Array(byDay.values)
        guard !observed.isEmpty else { return 0 }

        let flatMean = observed.reduce(0, +) / Double(observed.count)
        // Under three logged days a trend is noise; fall back to the flat mean.
        guard byDay.count >= 3, let origin = allDays.min() else { return flatMean }

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
        for day in allDays {
            if let logged = byDay[day] {
                total += logged
            } else {
                let x = day.timeIntervalSince(origin) / 86_400
                total += (intercept + slope * x).clamped(to: low...high)
            }
        }
        return total / Double(allDays.count)
    }

    /// Raw daily weight means (multiple same-day weigh-ins averaged).
    private func dailyWeightSeries(_ window: [DailyRecord]) -> [Point] {
        let cal = Calendar(identifier: .gregorian)
        var byDay: [Date: [Double]] = [:]
        for r in window {
            guard let w = r.weightKg else { continue }
            byDay[cal.startOfDay(for: r.date), default: []].append(w)
        }
        guard let origin = byDay.keys.min() else { return [] }
        return byDay.keys.sorted().map { day in
            let ws = byDay[day]!
            return Point(day: day.timeIntervalSince(origin) / 86_400,
                         value: ws.reduce(0, +) / Double(ws.count))
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

    /// Mifflin-St Jeor BMR (kcal/day).
    private func bmr(_ p: Prior, weightKg: Double) -> Double {
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
