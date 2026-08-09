import Foundation

/// Daily cardiovascular strain on a 0–100 scale — the exertion counterpart to
/// the recovery score, in the spirit of WHOOP's strain and Bevel's exertion.
///
/// **Same currency as the cardio ACWR, a different question.** Both are built on
/// Banister TRIMP (`CardioLoadAnalyzer.trimp`). ACWR asks whether load is ramping
/// too fast across weeks; strain asks how hard *today* was. Sharing TRIMP keeps
/// them consistent — a day that reads "hard" here is the same load the ACWR counts.
///
/// **Strength counts here, unlike the ACWR.** ACWR excludes lifting to keep
/// "cardio load" one unit; strain is total cardiovascular exertion, and an hour
/// under a heavy bar elevates heart rate much as an easy jog does. Any workout
/// carrying heart rate contributes; the engine is deliberately activity-agnostic.
///
/// **Normalised so most days sit mid-range.** The day's raw TRIMP is expressed
/// against a fixed physiological anchor — a genuinely demanding day — floored up
/// by your own recent peak. So an ordinary session lands well below 100, and only
/// a maximal day approaches it; a routinely high-volume athlete's own peak raises
/// the scale so their normal day isn't pegged. 100% is "a day as hard as your
/// hardest recent day, or a physiologically maximal one" — not an easy ceiling.
///
/// Workout-based: with no all-day heart rate it cannot speak to a rest day's
/// background exertion, so a day with no heart-rate-carrying workout reports no
/// data rather than an invented zero. See docs/ALGORITHMS.md §3.
struct StrainEngine: Sendable {

    /// A demanding day's TRIMP — roughly two hours at ~75% heart-rate reserve, or
    /// one hour near maximal. The 100% point for anyone whose recent peak hasn't
    /// exceeded it, which keeps ordinary training off the ceiling. See ALGORITHMS.
    static let referenceAnchorTrimp = 300.0

    /// Trailing window the personal peak is taken over. Six weeks tracks a
    /// changing base without one big day setting the scale for months.
    static let referenceWindowDays = 42

    enum Band: String, Sendable {
        case light = "Light"
        case moderate = "Moderate"
        case hard = "Hard"
        case allOut = "All out"
    }

    struct Result: Sendable, Equatable {
        let strain: Double            // 0…100, rounded
        let rawTrimp: Double          // the day's summed TRIMP
        let reference: Double         // the scale the day was measured against
        let band: Band
        /// Fraction of the day's workouts that carried heart rate; a present
        /// result always has some coverage (no-coverage days return nil).
        let dataCompleteness: Double
    }

    /// `records` should span at least the reference window ending at `day`.
    /// Returns nil when the day has no heart-rate-carrying workout to measure.
    func evaluate(records: [CardioRecord], on day: Date = .now,
                  restingHR: Double, age: Double, isFemale: Bool,
                  calendar: Calendar = .current) -> Result? {
        let maxHR = CardioLoadAnalyzer.estimatedMaxHeartRate(age: age)
        let dayBounds = DayBounds(day, calendar: calendar)

        let todays = records.filter { dayBounds.contains($0.date) }
        guard !todays.isEmpty else { return nil }
        let todayLoads = todays.compactMap {
            CardioLoadAnalyzer.trimp($0, restingHR: restingHR, maxHR: maxHR, isFemale: isFemale)
        }
        guard !todayLoads.isEmpty else { return nil } // workouts logged, none with HR
        let rawTrimp = todayLoads.reduce(0, +)
        let completeness = Double(todayLoads.count) / Double(todays.count)

        // Reference: the hardest day's TRIMP in the trailing window (today
        // included), floored by the anchor.
        let windowStart = calendar.date(byAdding: .day, value: -Self.referenceWindowDays, to: day) ?? day
        var dailyTotals: [Date: Double] = [:]
        for record in records where record.date > windowStart && record.date <= dayBounds.end {
            guard let load = CardioLoadAnalyzer.trimp(record, restingHR: restingHR,
                                                      maxHR: maxHR, isFemale: isFemale)
            else { continue }
            dailyTotals[calendar.startOfDay(for: record.date), default: 0] += load
        }
        let peak = dailyTotals.values.max() ?? rawTrimp
        let reference = max(peak, Self.referenceAnchorTrimp)

        let strain = (min(rawTrimp / reference, 1) * 100).rounded()
        return Result(strain: strain, rawTrimp: rawTrimp, reference: reference,
                      band: band(for: strain), dataCompleteness: completeness)
    }

    /// Bands the rounded value, so the label agrees with the number on screen —
    /// the same rule `RecoveryEngine` follows.
    private func band(for strain: Double) -> Band {
        switch strain {
        case ..<34: return .light
        case ..<67: return .moderate
        case ..<90: return .hard
        default: return .allOut
        }
    }
}
