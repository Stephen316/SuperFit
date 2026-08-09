import Foundation

/// One completed working set, reduced to the inputs that affect session effort.
struct StrainStrengthSet: Sendable, Equatable {
    let reps: Int
    let rir: Int?
}

/// A workout-shaped value input for `StrainEngine`. Imported cardio and locally
/// logged lifting both map here without coupling the pure engine to SwiftData.
struct StrainWorkout: Sendable {
    let date: Date
    let durationMinutes: Double
    var avgHeartRate: Double?
    var heartRateSegments: [HeartRateSegment] = []
    var sessionRPE: Int?
    var strengthSets: [StrainStrengthSet] = []
}

/// Daily workout strain on a 0–100 scale.
///
/// The engine uses the strongest available internal-load signal once per
/// workout: minute-level Banister TRIMP, then session RPE (duration × RPE), then
/// a completed-set/RIR estimate for lifting. This ordering prevents heart rate
/// and RPE from double-counting one session while allowing phone-only cardio and
/// strength sessions to contribute. Each load family is normalised separately;
/// unlike units are never added before normalisation.
struct StrainEngine: Sendable {
    /// Approximately a demanding cardiovascular day.
    static let referenceAnchorTrimp = 300.0
    /// One hard hour at RPE 10. Set-derived effort is converted to this scale.
    static let referenceAnchorEffort = 600.0
    static let referenceWindowDays = 42
    /// Avoid personalising a scale from a handful of isolated sessions.
    static let minimumReferenceDays = 10
    /// Below half-session coverage, complete RPE/set data is the more reliable
    /// representation of the workout than a few isolated watch minutes.
    static let minimumHeartRateCoverage = 0.5

    enum Band: String, Sendable {
        case light = "Light"
        case moderate = "Moderate"
        case hard = "Hard"
        case allOut = "All out"
    }

    struct Result: Sendable, Equatable {
        let strain: Double
        let rawTrimp: Double
        let rawEffort: Double
        let aerobicReference: Double
        let effortReference: Double
        let band: Band
        /// Average signal coverage across today's sessions. Minute HR gaps lower
        /// coverage; a valid RPE or completed strength log provides full coverage.
        let dataCompleteness: Double
    }

    func evaluate(workouts: [StrainWorkout], on day: Date = .now,
                  restingHR: Double?, age: Double, isFemale: Bool,
                  calendar: Calendar = .current) -> Result? {
        let maxHR = CardioLoadAnalyzer.estimatedMaxHeartRate(age: age)
        let bounds = DayBounds(day, calendar: calendar)
        let windowStart = calendar.date(byAdding: .day, value: -Self.referenceWindowDays,
                                        to: bounds.start) ?? bounds.start

        var aerobicByDay: [Date: Double] = [:]
        var effortByDay: [Date: Double] = [:]
        var todayCoverage: [Double] = []

        for workout in workouts
        where workout.date >= windowStart && workout.date < bounds.end {
            let dayKey = calendar.startOfDay(for: workout.date)
            let cardio = CardioRecord(date: workout.date,
                                      durationMinutes: workout.durationMinutes,
                                      avgHeartRate: workout.avgHeartRate,
                                      heartRateSegments: workout.heartRateSegments)
            if let restingHR,
               let trimp = CardioLoadAnalyzer.trimp(cardio, restingHR: restingHR,
                                                    maxHR: maxHR, isFemale: isFemale) {
                let coverage = heartRateCoverage(for: workout)
                let fallback = Self.fallbackEffort(for: workout)
                if coverage >= Self.minimumHeartRateCoverage || fallback == nil {
                    aerobicByDay[dayKey, default: 0] += trimp
                    if bounds.contains(workout.date) { todayCoverage.append(coverage) }
                    continue
                }
                effortByDay[dayKey, default: 0] += fallback ?? 0
                if bounds.contains(workout.date) { todayCoverage.append(1) }
                continue
            }

            if let effort = Self.fallbackEffort(for: workout) {
                effortByDay[dayKey, default: 0] += effort
                if bounds.contains(workout.date) { todayCoverage.append(1) }
            } else if bounds.contains(workout.date) {
                todayCoverage.append(0)
            }
        }

        let todayKey = bounds.start
        let rawTrimp = aerobicByDay[todayKey] ?? 0
        let rawEffort = effortByDay[todayKey] ?? 0
        guard rawTrimp > 0 || rawEffort > 0 else { return nil }

        let aerobicReference = reference(for: Array(aerobicByDay.values),
                                         anchor: Self.referenceAnchorTrimp)
        let effortReference = reference(for: Array(effortByDay.values),
                                        anchor: Self.referenceAnchorEffort)
        // Normalised components can be combined because each is now a share of
        // a demanding personal day, not raw TRIMP plus arbitrary set units.
        let normalised = rawTrimp / aerobicReference + rawEffort / effortReference
        let strain = (min(normalised, 1) * 100).rounded()
        let completeness = todayCoverage.isEmpty
            ? 0
            : todayCoverage.reduce(0, +) / Double(todayCoverage.count)
        return Result(strain: strain, rawTrimp: rawTrimp, rawEffort: rawEffort,
                      aerobicReference: aerobicReference, effortReference: effortReference,
                      band: band(for: strain), dataCompleteness: completeness)
    }

    /// Compatibility entry point for cardio-only callers and older tests.
    func evaluate(records: [CardioRecord], on day: Date = .now,
                  restingHR: Double, age: Double, isFemale: Bool,
                  calendar: Calendar = .current) -> Result? {
        evaluate(workouts: records.map {
            StrainWorkout(date: $0.date, durationMinutes: $0.durationMinutes,
                          avgHeartRate: $0.avgHeartRate,
                          heartRateSegments: $0.heartRateSegments)
        }, on: day, restingHR: restingHR, age: age, isFemale: isFemale,
        calendar: calendar)
    }

    /// RPE is preferred because it measures the person's internal response.
    /// When absent, completed working sets are estimated from reps and proximity
    /// to failure. Twenty hard-set equivalents map to the 600-point anchor.
    static func fallbackEffort(for workout: StrainWorkout) -> Double? {
        if let rpe = workout.sessionRPE, (1...10).contains(rpe),
           workout.durationMinutes > 0 {
            return workout.durationMinutes * Double(rpe)
        }
        guard !workout.strengthSets.isEmpty else { return nil }
        let units = workout.strengthSets.reduce(0.0) { total, set in
            guard set.reps > 0 else { return total }
            let repFactor = min(max(Double(set.reps) / 8, 0.5), 1.5)
            let proximity = 1 / (1 + 0.25 * Double(max(set.rir ?? 2, 0)))
            return total + repFactor * proximity
        }
        return units > 0 ? units * 30 : nil
    }

    private func heartRateCoverage(for workout: StrainWorkout) -> Double {
        guard workout.durationMinutes > 0 else { return 0 }
        guard !workout.heartRateSegments.isEmpty else {
            return workout.avgHeartRate == nil ? 0 : 1
        }
        let measured = workout.heartRateSegments.reduce(0) {
            $0 + max($1.durationMinutes, 0)
        }
        return min(measured / workout.durationMinutes, 1)
    }

    /// Personal scale uses a robust 95th percentile rather than a single peak.
    /// The fixed anchor remains until enough distinct training days exist.
    private func reference(for dailyLoads: [Double], anchor: Double) -> Double {
        let loads = dailyLoads.filter { $0 > 0 }.sorted()
        guard loads.count >= Self.minimumReferenceDays else { return anchor }
        let position = 0.95 * Double(loads.count - 1)
        let lower = Int(position.rounded(.down))
        let upper = Int(position.rounded(.up))
        let fraction = position - Double(lower)
        let percentile = loads[lower] + (loads[upper] - loads[lower]) * fraction
        return max(anchor, percentile)
    }

    private func band(for strain: Double) -> Band {
        switch strain {
        case ..<34: return .light
        case ..<67: return .moderate
        case ..<90: return .hard
        default: return .allOut
        }
    }
}
