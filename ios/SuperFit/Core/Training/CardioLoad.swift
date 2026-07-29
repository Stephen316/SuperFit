import Foundation

/// Value snapshot of one cardio session — pure input, decoupled from SwiftData.
struct CardioRecord: Sendable {
    let date: Date
    let durationMinutes: Double
    /// nil when the source recorded no heart rate. Not defaulted to anything:
    /// an unknown intensity is what makes the load unknown.
    let avgHeartRate: Double?
}

/// Training load and ACWR for cardio, kept separate from lifting.
///
/// **Why separate rather than one combined number.** Lifting load is tonnage
/// (kg x reps) and cardio load is duration x intensity. They have no shared unit,
/// and summing them would let an easy 90-minute walk cancel a heavy squat
/// session. Two ratios each answer a question you can act on; one blended ratio
/// answers neither.
///
/// **Why this is not wired into the recovery score.** `RecoveryEngine` bands ACWR
/// from lifting tonnage today, and every stored recovery score was computed that
/// way. Feeding a second load source in would move historical scores without any
/// validation against real data that this app has yet collected. It is reported
/// as its own figure until there is enough logged cardio to check it against.
struct CardioLoadAnalyzer: Sendable {

    /// Banister TRIMP coefficients. The exponential is what makes hard minutes
    /// count for more than easy ones; a linear duration x intensity would rate
    /// two easy hours the same as one hard one.
    private static let maleA = 0.64, maleB = 1.92
    private static let femaleA = 0.86, femaleB = 1.67

    /// Fraction of workouts in a window that must carry heart rate before an
    /// ACWR is reported at all.
    ///
    /// Workouts without heart rate have unknown load, and substituting duration
    /// would mix two units in one series. Excluding them instead biases the ratio
    /// whenever the gaps fall unevenly between the two windows: measured at 14%
    /// distortion with a 0.8 gate, ~7% at 0.9. A watch records heart rate on
    /// essentially every workout, so this only bites on manual entries.
    static let minimumHeartRateCoverage = 0.9

    /// Tanaka: less biased than 220 - age, particularly over 40.
    static func estimatedMaxHeartRate(age: Double) -> Double { 208 - 0.7 * age }

    /// Load for one session, or nil when intensity is unknown.
    static func trimp(_ record: CardioRecord, restingHR: Double, maxHR: Double,
                      isFemale: Bool) -> Double? {
        guard let avg = record.avgHeartRate, record.durationMinutes > 0 else { return nil }
        let reserve = maxHR - restingHR
        guard reserve > 0 else { return nil }
        let ratio = min(max((avg - restingHR) / reserve, 0), 1)
        let a = isFemale ? femaleA : maleA
        let b = isFemale ? femaleB : maleB
        return record.durationMinutes * ratio * a * Foundation.exp(b * ratio)
    }

    struct Result: Sendable, Equatable {
        let ratio: Double
        let acuteLoad: Double
        let chronicWeeklyLoad: Double

        /// Same bands as the lifting ACWR, closed at 1.3 for the same reason.
        var band: Band {
            switch ratio {
            case ..<0.8: return .detraining
            case 0.8...1.3: return .optimal
            case ..<1.5: return .elevated
            default: return .spike
            }
        }

        enum Band: String, Sendable {
            case detraining = "Detraining"
            case optimal = "Optimal"
            case elevated = "Elevated"
            case spike = "Spike risk"
        }
    }

    /// Acute (7-day) over chronic (28-day average week), or nil when there isn't
    /// enough measured intensity to answer honestly.
    func acwr(records: [CardioRecord], on day: Date = .now,
              restingHR: Double, age: Double, isFemale: Bool,
              calendar: Calendar = .current) -> Result? {
        let maxHR = Self.estimatedMaxHeartRate(age: age)
        let end = day
        let acuteStart = calendar.date(byAdding: .day, value: -7, to: end) ?? end
        let chronicStart = calendar.date(byAdding: .day, value: -28, to: end) ?? end

        func window(from start: Date) -> (loads: [Double], coverage: Double) {
            // Half-open at the far end: `>= start` spans 8 days for a 7-day
            // window, catching a fifth session in a four-a-week routine and
            // reporting a steady block as a 1.25 ramp.
            let inWindow = records.filter { $0.date > start && $0.date <= end }
            guard !inWindow.isEmpty else { return ([], 1) }
            let loads = inWindow.compactMap {
                Self.trimp($0, restingHR: restingHR, maxHR: maxHR, isFemale: isFemale)
            }
            return (loads, Double(loads.count) / Double(inWindow.count))
        }

        let acute = window(from: acuteStart)
        let chronic = window(from: chronicStart)
        guard acute.coverage >= Self.minimumHeartRateCoverage,
              chronic.coverage >= Self.minimumHeartRateCoverage,
              !chronic.loads.isEmpty
        else { return nil }

        let acuteLoad = acute.loads.reduce(0, +)
        let chronicWeekly = chronic.loads.reduce(0, +) / 4
        guard chronicWeekly > 0 else { return nil }
        return Result(ratio: acuteLoad / chronicWeekly,
                      acuteLoad: acuteLoad,
                      chronicWeeklyLoad: chronicWeekly)
    }
}
