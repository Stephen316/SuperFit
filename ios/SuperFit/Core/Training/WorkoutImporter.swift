import Foundation

/// Decides what to do with workouts fetched from a health source.
///
/// Pure and dependency-free so the rules can be tested without HealthKit or a
/// store. The service layer applies the decisions; nothing here touches
/// SwiftData.
///
/// **Idempotency.** `HKObserverQuery` fires on every change to the workout
///    store, not once per new workout, and the app re-imports a rolling window
///    on each sync. Keying on the source's own identifier means re-importing the
///    same workout updates it instead of producing a second copy.
///
/// Time-based reconciliation with a locally logged session happens after import.
/// The watch record must remain available because it contains the heart-rate
/// stream that the set-by-set phone log does not. `WorkoutTimeMatcher` joins the
/// two views of the same physical session without double-counting it.
enum WorkoutImporter {

    enum Action: String, Equatable, Sendable {
        case insert
        /// Already stored under this identifier — refresh its metrics. A watch
        /// saves the workout when it ends and revises it as the phone syncs
        /// route and heart-rate data, so later reads carry more than the first.
        case update
        case skipDuplicateInBatch
    }

    struct Decision: Equatable, Sendable {
        let externalID: String
        let action: Action
    }

    static func decide(samples: [WorkoutSample],
                       existingExternalIDs: Set<String>) -> [Decision] {
        var seen: Set<String> = []
        return samples.map { sample in
            let id = sample.externalID

            if seen.contains(id) {
                return Decision(externalID: id, action: .skipDuplicateInBatch)
            }
            seen.insert(id)

            return Decision(externalID: id,
                            action: existingExternalIDs.contains(id) ? .update : .insert)
        }
    }
}

/// Pairs independently recorded workouts using their shared time rather than an
/// identifier: HealthKit and SuperFit assign different IDs to the same session.
/// Each item can be claimed once, so one long-running watch workout cannot be
/// attached to two phone sessions.
enum WorkoutTimeMatcher {
    static let overlapThreshold = 0.5

    static func matches(workouts: [DateInterval],
                        sessions: [DateInterval]) -> [Int: Int] {
        struct Candidate {
            let workout: Int
            let session: Int
            let overlap: Double
            let startDifference: Double
        }

        var candidates: [Candidate] = []
        for (workoutIndex, workout) in workouts.enumerated() where workout.duration > 0 {
            for (sessionIndex, session) in sessions.enumerated() where session.duration > 0 {
                guard let shared = workout.intersection(with: session), shared.duration > 0 else {
                    continue
                }
                // Compare against the shorter recording. A watch often starts
                // earlier or ends later while still representing the same lift.
                let fraction = shared.duration / min(workout.duration, session.duration)
                guard fraction >= overlapThreshold else { continue }
                candidates.append(Candidate(
                    workout: workoutIndex,
                    session: sessionIndex,
                    overlap: fraction,
                    startDifference: abs(workout.start.timeIntervalSince(session.start))))
            }
        }

        candidates.sort {
            if $0.overlap != $1.overlap { return $0.overlap > $1.overlap }
            if $0.startDifference != $1.startDifference {
                return $0.startDifference < $1.startDifference
            }
            if $0.workout != $1.workout { return $0.workout < $1.workout }
            return $0.session < $1.session
        }

        var claimedWorkouts: Set<Int> = []
        var claimedSessions: Set<Int> = []
        var result: [Int: Int] = [:]
        for candidate in candidates
        where !claimedWorkouts.contains(candidate.workout)
            && !claimedSessions.contains(candidate.session) {
            result[candidate.workout] = candidate.session
            claimedWorkouts.insert(candidate.workout)
            claimedSessions.insert(candidate.session)
        }
        return result
    }
}
