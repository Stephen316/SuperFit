import Testing
import Foundation
import SwiftData
@testable import SuperFit

@MainActor
struct DataArchiveTests {

    /// A throwaway store per test — no file, no CloudKit, no shared state.
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(AppSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        return ModelContext(container)
    }

    private func seed(_ context: ModelContext) {
        let profile = UserProfile()
        profile.heightCm = 183
        profile.goal = .recomposition
        context.insert(profile)

        context.insert(BodyMetrics(date: Date(timeIntervalSince1970: 1_700_000_000),
                                   weightKg: 82.4))

        let log = NutritionLog(date: Date(timeIntervalSince1970: 1_700_000_000), meal: .lunch)
        log.foodName = "Chicken breast"
        log.servingGrams = 180
        log.kcal = 297
        log.proteinG = 56
        log.micros = [.iron: 1.9, .potassium: 460]
        context.insert(log)

        let exercise = Exercise(name: "My Custom Press", category: .barbell,
                                tension: [.chest: 5, .tricepsLateral: 3], isCustom: true)
        context.insert(exercise)

        let session = TrainingSession(startedAt: Date(timeIntervalSince1970: 1_700_100_000),
                                      templateName: "Push")
        context.insert(session)
        let set = SetEntry(order: 1, exerciseID: exercise.id, weightKg: 100, reps: 5)
        set.rir = 2
        set.session = session
        context.insert(set)

        let supplement = Supplement(name: "My Blend", category: .protein,
                                    servingLabel: "30 g scoop", servingGrams: 30,
                                    profile: NutrientProfile(kcal: 120, proteinG: 24),
                                    isCustom: true)
        context.insert(supplement)
        let entry = SupplementEntry(supplementID: supplement.id, kind: .daily)
        entry.startedOn = Date(timeIntervalSince1970: 1_700_000_000)
        context.insert(entry)

        try? context.save()
    }

    // MARK: Round trip

    @Test func exportCapturesEverythingUserCreated() throws {
        let context = try makeContext()
        seed(context)

        let archive = DataArchiveService.export(context: context)
        #expect(archive.profile?.heightCm == 183)
        #expect(archive.bodyMetrics.count == 1)
        #expect(archive.nutritionLogs.count == 1)
        #expect(archive.exercises.count == 1)
        #expect(archive.sessions.count == 1)
        #expect(archive.sessions.first?.sets.count == 1)
        #expect(archive.supplements.count == 1)
        #expect(archive.supplementEntries.count == 1)
    }

    @Test func encodeDecodeSurvivesDatesAndNestedValues() throws {
        let context = try makeContext()
        seed(context)

        let data = try DataArchiveService.encode(DataArchiveService.export(context: context))
        let restored = try DataArchiveService.decode(data)

        #expect(restored.version == DataArchive.currentVersion)
        #expect(restored.bodyMetrics.first?.weightKg == 82.4)
        #expect(restored.sessions.first?.sets.first?.rir == 2)
        #expect(restored.nutritionLogs.first?.micros.isEmpty == false)
    }

    /// The whole point: a backup restored into an empty install must reproduce
    /// the data, not an approximation of it.
    @Test func restoringIntoAnEmptyStoreReproducesTheData() throws {
        let source = try makeContext()
        seed(source)
        let archive = try DataArchiveService.decode(
            DataArchiveService.encode(DataArchiveService.export(context: source)))

        let fresh = try makeContext()
        DataArchiveService.restore(archive, mode: .merge, context: fresh)

        let logs = try fresh.fetch(FetchDescriptor<NutritionLog>())
        #expect(logs.count == 1)
        #expect(logs.first?.foodName == "Chicken breast")
        #expect(logs.first?.kcal == 297)
        #expect(logs.first?.micros[.iron] == 1.9)

        let sessions = try fresh.fetch(FetchDescriptor<TrainingSession>())
        #expect(sessions.count == 1)
        #expect(sessions.first?.sets?.count == 1)
        #expect(sessions.first?.sets?.first?.weightKg == 100)

        let weights = try fresh.fetch(FetchDescriptor<BodyMetrics>())
        #expect(weights.first?.weightKg == 82.4)
    }

    // MARK: Merge safety

    /// Restoring the same file twice must not double anything — the common
    /// accident, and the one that would quietly corrupt every average.
    @Test func mergingTheSameArchiveTwiceIsIdempotent() throws {
        let context = try makeContext()
        seed(context)
        let archive = DataArchiveService.export(context: context)

        let fresh = try makeContext()
        DataArchiveService.restore(archive, mode: .merge, context: fresh)
        let afterFirst = try fresh.fetch(FetchDescriptor<NutritionLog>()).count
        let weightsFirst = try fresh.fetch(FetchDescriptor<BodyMetrics>()).count

        DataArchiveService.restore(archive, mode: .merge, context: fresh)
        #expect(try fresh.fetch(FetchDescriptor<NutritionLog>()).count == afterFirst)
        #expect(try fresh.fetch(FetchDescriptor<BodyMetrics>()).count == weightsFirst)
        #expect(try fresh.fetch(FetchDescriptor<TrainingSession>()).count == 1)
        #expect(try fresh.fetch(FetchDescriptor<Supplement>()).count == 1)
    }

    @Test func mergeKeepsDataThatIsNotInTheArchive() throws {
        let context = try makeContext()
        seed(context)
        let archive = DataArchiveService.export(context: context)

        let fresh = try makeContext()
        let localOnly = NutritionLog(date: Date(timeIntervalSince1970: 1_800_000_000),
                                     meal: .dinner)
        localOnly.foodName = "Logged after the backup"
        fresh.insert(localOnly)
        try fresh.save()

        DataArchiveService.restore(archive, mode: .merge, context: fresh)
        let names = try fresh.fetch(FetchDescriptor<NutritionLog>()).compactMap(\.foodName)
        #expect(names.contains("Logged after the backup"))
        #expect(names.contains("Chicken breast"))
    }

    @Test func replaceClearsExistingDataFirst() throws {
        let context = try makeContext()
        seed(context)
        let archive = DataArchiveService.export(context: context)

        let fresh = try makeContext()
        let stale = NutritionLog(date: Date(timeIntervalSince1970: 1_800_000_000), meal: .dinner)
        stale.foodName = "From the other account"
        fresh.insert(stale)
        try fresh.save()

        DataArchiveService.restore(archive, mode: .replace, context: fresh)
        let names = try fresh.fetch(FetchDescriptor<NutritionLog>()).compactMap(\.foodName)
        #expect(!names.contains("From the other account"))
        #expect(names.contains("Chicken breast"))
    }

    /// Built-in exercises are re-seeded on every launch with fresh ids, so an
    /// id-only check would duplicate the whole catalog on restore.
    @Test func restoreDoesNotDuplicateSeededExercisesByName() throws {
        let context = try makeContext()
        ExerciseLibrary.seedIfNeeded(context: context)
        let archive = DataArchiveService.export(context: context)
        let seededCount = try context.fetch(FetchDescriptor<Exercise>()).count

        // A fresh install seeds its own copies with different ids.
        let fresh = try makeContext()
        ExerciseLibrary.seedIfNeeded(context: fresh)
        DataArchiveService.restore(archive, mode: .merge, context: fresh)

        #expect(try fresh.fetch(FetchDescriptor<Exercise>()).count == seededCount)
    }

    // MARK: Guards

    @Test func rejectsAnArchiveFromANewerVersion() throws {
        var archive = DataArchive()
        archive.version = DataArchive.currentVersion + 1
        // Must go through the service's encoder: a bare JSONEncoder writes dates
        // as numbers, so decode fails on exportedAt before reaching the version
        // guard this test exists to exercise.
        let data = try DataArchiveService.encode(archive)
        #expect(throws: DataArchiveService.ArchiveError.self) {
            try DataArchiveService.decode(data)
        }
    }

    @Test func eraseRemovesEverything() throws {
        let context = try makeContext()
        seed(context)
        DataArchiveService.eraseAll(context: context)

        #expect(try context.fetch(FetchDescriptor<NutritionLog>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<TrainingSession>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<BodyMetrics>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Supplement>()).isEmpty)
    }

    // MARK: Sign-out must not touch data

    @Test func signingOutLeavesDataIntact() throws {
        let context = try makeContext()
        seed(context)
        let before = try context.fetch(FetchDescriptor<NutritionLog>()).count

        let account = AccountManager()
        account.completeSignIn(userID: "test.user.id", fullName: nil)
        #expect(account.isSignedIn)
        account.signOut()
        #expect(!account.isSignedIn)

        #expect(try context.fetch(FetchDescriptor<NutritionLog>()).count == before)
    }
}
