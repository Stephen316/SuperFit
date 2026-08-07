import Foundation

/// Turns stored training sessions into the flat `LiftRecord`s the analyzers read.
///
/// **One definition of "trained": a completed, logged set.** A set the user
/// never ticked is a plan, not a performed set, and every surface that reads
/// training volume — the muscle diagram, the weekly table, the history charts,
/// the recovery load — has to agree on that or they drift apart. Keeping the
/// filter here means the rule is stated once.
enum TrainingRecords {

    /// `LiftRecord`s for the completed sets across `sessions`.
    ///
    /// `fractions` maps an exercise id to its bodyweight fraction, so unweighted
    /// work still contributes load; a missing id contributes none.
    static func completed(_ sessions: [TrainingSession],
                          fractions: [UUID: Double]) -> [LiftRecord] {
        sessions.flatMap { session in
            (session.sets ?? []).compactMap { set -> LiftRecord? in
                guard let id = set.exerciseID, set.completedAt != nil else { return nil }
                return LiftRecord(date: session.startedAt, exerciseID: id,
                                  weightKg: set.weightKg ?? 0, reps: set.reps,
                                  isWarmup: set.isWarmup,
                                  bodyweightFraction: fractions[id] ?? 0)
            }
        }
    }
}
