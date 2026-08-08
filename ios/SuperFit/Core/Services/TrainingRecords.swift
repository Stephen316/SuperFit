import Foundation

/// Turns stored training sessions into the flat `LiftRecord`s the analyzers read.
///
/// **One definition of "trained": a completed, logged set.** A set the user
/// never ticked is a plan, not a performed set, and every surface that reads
/// training volume — the muscle diagram, the weekly table, the history charts,
/// the recovery load — has to agree on that or they drift apart. Keeping the
/// filter here means the rule is stated once.
enum TrainingRecords {

    /// One set copied forward as a plan. Completion is intentionally absent:
    /// the user has not performed any work in the new session yet.
    struct PlannedSet: Equatable {
        let order: Int
        let exerciseID: UUID
        let weightKg: Double?
        let reps: Int
        let rir: Int?
        let restSeconds: Int?
        let isWarmup: Bool
    }

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

    /// The newest completed workout with this saved name, copied as an
    /// unchecked plan and restricted to exercises still in the template.
    static func repeatedPlan(templateName: String,
                             exerciseIDs: [UUID],
                             sessions: [TrainingSession]) -> [PlannedSet] {
        let allowed = Set(exerciseIDs)
        guard !allowed.isEmpty else { return [] }
        let completed = sessions.filter { session in
            (session.sets ?? []).contains { $0.completedAt != nil && !$0.isWarmup }
        }
        let named = completed
            .filter { $0.templateName?.caseInsensitiveCompare(templateName) == .orderedSame }
            .max(by: { $0.startedAt < $1.startedAt })
        // Templates created before repeat-prefill existed did not tag the
        // session that created them. Exact exercise order recovers that first
        // workout without confusing a merely similar routine for this one.
        let matchingExercises = completed
            .filter { orderedExerciseIDs(in: $0) == exerciseIDs }
            .max(by: { $0.startedAt < $1.startedAt })
        guard let previous = named ?? matchingExercises else { return [] }

        return (previous.sets ?? [])
            .sorted { $0.order < $1.order }
            .compactMap { set in
                guard let exerciseID = set.exerciseID,
                      allowed.contains(exerciseID) else { return nil }
                return PlannedSet(order: set.order,
                                  exerciseID: exerciseID,
                                  weightKg: set.weightKg,
                                  reps: set.reps,
                                  rir: set.rir,
                                  restSeconds: set.restSeconds,
                                  isWarmup: set.isWarmup)
            }
    }

    private static func orderedExerciseIDs(in session: TrainingSession) -> [UUID] {
        var seen = Set<UUID>()
        return (session.sets ?? [])
            .sorted { $0.order < $1.order }
            .compactMap { set in
                guard let id = set.exerciseID, seen.insert(id).inserted else { return nil }
                return id
            }
    }
}
