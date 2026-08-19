import Testing
import Foundation
import SwiftData
@testable import SuperFit

/// Only completed sets become training records — the one rule the diagram, the
/// history charts and the recovery load all depend on.
@MainActor
struct TrainingRecordsTests {

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(AppSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        return ModelContext(container)
    }

    private func session(_ context: ModelContext,
                         sets: [(weight: Double, reps: Int, done: Bool)]) -> TrainingSession {
        let exercise = UUID()
        let s = TrainingSession(startedAt: .now)
        context.insert(s)
        for (i, spec) in sets.enumerated() {
            let e = SetEntry(order: i, exerciseID: exercise, weightKg: spec.weight, reps: spec.reps)
            e.completedAt = spec.done ? .now : nil
            e.session = s
            context.insert(e)
        }
        return s
    }

    @Test func onlyCompletedSetsBecomeRecords() throws {
        let context = try makeContext()
        let s = session(context, sets: [
            (60, 8, true),    // done
            (60, 8, true),    // done
            (60, 8, false),   // planned, not ticked
        ])
        let records = TrainingRecords.completed([s], fractions: [:])
        #expect(records.count == 2, "the unticked set is not a performed set")
    }

    @Test func aSessionWithNothingTickedProducesNoRecords() throws {
        let context = try makeContext()
        let s = session(context, sets: [(60, 8, false), (60, 8, false)])
        #expect(TrainingRecords.completed([s], fractions: [:]).isEmpty)
    }

    /// nil weight — a set left at "--" but ticked — carries zero load rather than
    /// crashing the sum.
    @Test func aTickedSetWithNoWeightCarriesZeroLoad() throws {
        let context = try makeContext()
        let exercise = UUID()
        let s = TrainingSession(startedAt: .now)
        context.insert(s)
        let e = SetEntry(order: 0, exerciseID: exercise, weightKg: nil, reps: 8)
        e.completedAt = .now
        e.session = s
        context.insert(e)
        let records = TrainingRecords.completed([s], fractions: [:])
        #expect(records.count == 1)
        #expect(records.first?.weightKg == 0)
    }

    @Test func bodyweightFractionIsCarried() throws {
        let context = try makeContext()
        let s = session(context, sets: [(0, 10, true)])
        let id = try #require(s.sets?.first?.exerciseID)
        let records = TrainingRecords.completed([s], fractions: [id: 1.0])
        #expect(records.first?.bodyweightFraction == 1.0)
    }

    /// Starting a saved workout repeats the newest completed version, including
    /// set details, but ignores a newer abandoned attempt and removed exercises.
    @Test func savedWorkoutRepeatsTheLatestCompletedPlan() throws {
        let context = try makeContext()
        let keptExercise = UUID()
        let removedExercise = UUID()

        let older = TrainingSession(
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            templateName: "Pull")
        context.insert(older)
        let olderSet = SetEntry(order: 0, exerciseID: keptExercise,
                                weightKg: 50, reps: 10)
        olderSet.completedAt = older.startedAt
        olderSet.session = older
        context.insert(olderSet)

        let latest = TrainingSession(
            startedAt: Date(timeIntervalSince1970: 1_710_000_000),
            templateName: "Pull")
        context.insert(latest)
        let warmup = SetEntry(order: 0, exerciseID: keptExercise,
                              weightKg: 40, reps: 12)
        warmup.rir = 4
        warmup.restSeconds = 60
        warmup.isWarmup = true
        warmup.completedAt = latest.startedAt
        warmup.session = latest
        context.insert(warmup)
        let working = SetEntry(order: 1, exerciseID: keptExercise,
                               weightKg: 70, reps: 8)
        working.rir = 2
        working.restSeconds = 180
        working.completedAt = latest.startedAt
        working.session = latest
        context.insert(working)
        let removed = SetEntry(order: 2, exerciseID: removedExercise,
                               weightKg: 90, reps: 6)
        removed.completedAt = latest.startedAt
        removed.session = latest
        context.insert(removed)

        let abandoned = TrainingSession(
            startedAt: Date(timeIntervalSince1970: 1_720_000_000),
            templateName: "Pull")
        context.insert(abandoned)
        let abandonedSet = SetEntry(order: 0, exerciseID: keptExercise,
                                    weightKg: 100, reps: 3)
        abandonedSet.session = abandoned
        context.insert(abandonedSet)

        let plan = TrainingRecords.repeatedPlan(
            templateName: "pull",
            exerciseIDs: [keptExercise],
            sessions: [older, latest, abandoned])

        #expect(plan.count == 2)
        #expect(plan[0] == .init(order: 0, exerciseID: keptExercise,
                                 weightKg: 40, reps: 12, rir: 4,
                                 restSeconds: 60, isWarmup: true))
        #expect(plan[1] == .init(order: 1, exerciseID: keptExercise,
                                 weightKg: 70, reps: 8, rir: 2,
                                 restSeconds: 180, isWarmup: false))
    }

    @Test func savedWorkoutLimitIsEight() {
        #expect(WorkoutTemplate.canCreate(savedCount: 7))
        #expect(!WorkoutTemplate.canCreate(savedCount: 8))
        #expect(!WorkoutTemplate.canCreate(savedCount: 9))
    }

    /// Older templates did not tag the session that created them. An exact
    /// exercise-order match still makes that workout available for first reuse.
    @Test func savedWorkoutFindsItsLegacyUntaggedSession() throws {
        let context = try makeContext()
        let row = UUID()
        let curl = UUID()
        let session = TrainingSession(
            startedAt: Date(timeIntervalSince1970: 1_700_000_000))
        context.insert(session)
        let first = SetEntry(order: 0, exerciseID: row, weightKg: 75, reps: 8)
        first.completedAt = session.startedAt
        first.session = session
        context.insert(first)
        let second = SetEntry(order: 1, exerciseID: curl, weightKg: 15, reps: 12)
        second.completedAt = session.startedAt
        second.session = session
        context.insert(second)

        let plan = TrainingRecords.repeatedPlan(
            templateName: "Pull",
            exerciseIDs: [row, curl],
            sessions: [session])

        #expect(plan.map(\.exerciseID) == [row, curl])
        #expect(plan.map(\.weightKg) == [75, 15])
    }
}
