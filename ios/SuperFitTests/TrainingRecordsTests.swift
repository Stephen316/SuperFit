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
}
