import Foundation

/// The lean-mass figure the engines should use, and how stale it may be.
///
/// **Why this is not just "the newest row".**
///
/// Lean mass only arrives with a body-composition reading — a smart scale, or a
/// figure the user entered. A manual weigh-in carries none. So reading it off the
/// most recent `BodyMetrics` row meant it appeared and vanished with whatever
/// happened to be logged last, and two things swung with it:
///
/// - the protein target, between 2.4 g/kg of lean mass and 2.0 g/kg of
///   bodyweight — about 30 g for an 80 kg lifter at 15% body fat;
/// - the basal estimate, between Katch-McArdle and Mifflin-St Jeor.
///
/// Step on a smart scale on Monday and type a number on Tuesday, and the app
/// changed its mind about both, every day, on no new evidence.
///
/// Carrying the last known reading forward is right because the quantity is
/// right: lean mass moves over months, not overnight. What it must not do is
/// carry forward indefinitely — a composition figure from last spring describes
/// somebody else — so it expires.
enum BodyComposition {

    /// How long a composition reading stands in for the current one.
    ///
    /// Thirty days: long enough to survive a holiday or a broken scale, short
    /// enough that a real recomposition is not still being described by a
    /// measurement that predates it. Anyone using a smart scale re-reads it
    /// daily and never reaches this bound; it exists for the people who measured
    /// once and stopped.
    static let maxAgeDays = 30.0

    /// The most recent usable lean-mass reading, or nil when there isn't one
    /// inside the window.
    static func recentLeanMassKg(_ metrics: [BodyMetrics], asOf: Date = .now) -> Double? {
        let cutoff = asOf.addingTimeInterval(-maxAgeDays * 86_400)
        return metrics
            .filter { $0.date >= cutoff }
            // Zero and negative are not measurements. A lean mass above
            // bodyweight is a bad entry rather than a person, and it would push
            // the Katch-McArdle basal above anything real.
            .compactMap { row -> (Date, Double)? in
                guard let lean = row.leanMassKg, lean > 0, lean <= row.weightKg else { return nil }
                return (row.date, lean)
            }
            .max { $0.0 < $1.0 }?.1
    }
}
