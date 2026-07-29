import Foundation

/// Decides what to do with workouts fetched from a health source.
///
/// Pure and dependency-free so the rules can be tested without HealthKit or a
/// store. The service layer applies the decisions; nothing here touches
/// SwiftData.
///
/// Two things make this more than a plain insert:
///
/// 1. **Idempotency.** `HKObserverQuery` fires on every change to the workout
///    store, not once per new workout, and the app re-imports a rolling window
///    on each sync. Keying on the source's own identifier means re-importing the
///    same workout updates it instead of producing a second copy.
/// 2. **Strength overlap.** A gym session logged in the app set-by-set is richer
///    than the watch's "Traditional Strength Training" block covering the same
///    hour. Importing both would double the week's training history and show two
///    entries for one session.
enum WorkoutImporter {

    enum Action: String, Equatable, Sendable {
        case insert
        /// Already stored under this identifier — refresh its metrics. A watch
        /// saves the workout when it ends and revises it as the phone syncs
        /// route and heart-rate data, so later reads carry more than the first.
        case update
        case skipLoggedStrength
        case skipDuplicateInBatch
    }

    struct Decision: Equatable, Sendable {
        let externalID: String
        let action: Action
    }

    /// Fraction of a strength workout that must sit inside a logged session
    /// before it counts as the same session. Watch and phone rarely agree on the
    /// exact minute — the watch keeps running while you rack the last set — so
    /// requiring containment would never match.
    static let strengthOverlapThreshold = 0.5

    static func decide(samples: [WorkoutSample],
                       existingExternalIDs: Set<String>,
                       loggedStrengthSessions: [DateInterval] = []) -> [Decision] {
        var seen: Set<String> = []
        return samples.map { sample in
            let id = sample.externalID

            if seen.contains(id) {
                return Decision(externalID: id, action: .skipDuplicateInBatch)
            }
            seen.insert(id)

            if sample.activity.isStrength,
               overlapsLoggedSession(sample, sessions: loggedStrengthSessions) {
                return Decision(externalID: id, action: .skipLoggedStrength)
            }

            return Decision(externalID: id,
                            action: existingExternalIDs.contains(id) ? .update : .insert)
        }
    }

    static func overlapsLoggedSession(_ sample: WorkoutSample,
                                      sessions: [DateInterval]) -> Bool {
        let workout = DateInterval(start: sample.start, end: max(sample.end, sample.start))
        guard workout.duration > 0 else { return false }
        return sessions.contains { session in
            guard let shared = session.intersection(with: workout) else { return false }
            return shared.duration / workout.duration >= strengthOverlapThreshold
        }
    }
}
