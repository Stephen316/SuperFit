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

    var defaultProteinPerKg: Double {
        switch self {
        case .fatLoss, .recomposition: return 2.0
        case .maintenance: return 1.8
        case .muscleGain: return 1.8
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
        let avgIntake = intakes.isEmpty ? 0 : intakes.reduce(0, +) / Double(intakes.count)

        let rawTDEE = avgIntake - slopePerDay * Self.kcalPerKg

        let coverage = Double(intakes.count) / Double(max(windowDays, 1))
        let weighIns = smoothed.count
        let dataMaturity = min(1, Double(windowDays) / 14)
        let weighInDensity = min(1, Double(weighIns) / (Double(windowDays) / 3))
        let confidence = (coverage * dataMaturity * weighInDensity)
            .clamped(to: 0...1)

        let priorTDEE = bmr(prior, weightKg: smoothed.last?.value ?? 75)
            * prior.activity.factor

        let blended = intakes.isEmpty
            ? priorTDEE
            : confidence * rawTDEE + (1 - confidence) * priorTDEE

        return TDEEEstimate(
            tdeeKcal: blended.rounded(),
            confidence: confidence,
            trendSlopeKgPerWeek: slopePerWeek,
            avgIntakeKcal: avgIntake.rounded(),
            smoothedWeightKg: smoothed.last?.value ?? 0,
            windowDays: windowDays
        )
    }

    /// Calorie target for a goal, guard-railed so weekly weight change stays in a
    /// muscle-retention / lean-gain safe band relative to bodyweight.
    func calorieTarget(tdee: TDEEEstimate, goal: FitnessGoal, bodyweightKg: Double) -> Double {
        let raw = tdee.tdeeKcal * (1 + goal.calorieOffset)

        let maxLossKcal = bodyweightKg * 0.01 * Self.kcalPerKg / 7   // 1%/wk
        let maxGainKcal = bodyweightKg * 0.005 * Self.kcalPerKg / 7  // 0.5%/wk
        let floor = tdee.tdeeKcal - maxLossKcal
        let ceiling = tdee.tdeeKcal + maxGainKcal
        return raw.clamped(to: floor...ceiling).rounded()
    }

    // MARK: - Internals

    private struct Point: Sendable { let day: Double; let value: Double }

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
