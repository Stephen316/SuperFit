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

        context.insert(HydrationSettings(dailyGoalMl: 2_800))

        context.insert(BodyMetrics(date: Date(timeIntervalSince1970: 1_700_000_000),
                                   weightKg: 82.4))

        let log = NutritionLog(date: Date(timeIntervalSince1970: 1_700_000_000), meal: .lunch)
        log.foodName = "Chicken breast"
        log.servingGrams = 180
        log.kcal = 297
        log.proteinG = 56
        log.micros = [.iron: 1.9, .potassium: 460]
        context.insert(log)

        context.insert(HydrationLog(
            date: Date(timeIntervalSince1970: 1_700_000_000),
            millilitres: 1_750))

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
        #expect(archive.hydration?.count == 1)
        #expect(archive.hydrationGoalMl == 2_800)
        #expect(archive.exercises.count == 1)
        #expect(archive.sessions.count == 1)
        #expect(archive.sessions.first?.sets.count == 1)
        #expect(archive.supplements.count == 1)
        #expect(archive.supplementEntries.count == 1)
    }

    @Test func backgroundExporterCapturesSavedData() async throws {
        let context = try makeContext()
        seed(context)

        let archive = await DataArchiveExporter(modelContainer: context.container).export()
        #expect(archive.profile?.heightCm == 183)
        #expect(archive.nutritionLogs.first?.foodName == "Chicken breast")
        #expect(archive.sessions.first?.sets.first?.weightKg == 100)
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
        #expect(restored.hydration?.first?.millilitres == 1_750)
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
        let hydration = try fresh.fetch(FetchDescriptor<HydrationLog>())
        #expect(hydration.count == 1)
        #expect(hydration.first?.millilitres == 1_750)
        #expect(try fresh.fetch(FetchDescriptor<HydrationSettings>()).first?.dailyGoalMl == 2_800)
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
        let hydrationFirst = try fresh.fetch(FetchDescriptor<HydrationLog>()).count

        DataArchiveService.restore(archive, mode: .merge, context: fresh)
        #expect(try fresh.fetch(FetchDescriptor<NutritionLog>()).count == afterFirst)
        #expect(try fresh.fetch(FetchDescriptor<BodyMetrics>()).count == weightsFirst)
        #expect(try fresh.fetch(FetchDescriptor<TrainingSession>()).count == 1)
        #expect(try fresh.fetch(FetchDescriptor<Supplement>()).count == 1)
        #expect(try fresh.fetch(FetchDescriptor<HydrationLog>()).count == hydrationFirst)
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

    /// A stale merge previously overwrote all 6 archived profile fields; the
    /// current profile must survive merge, while replace must restore all 6.
    @Test func mergePreservesCurrentProfileAndReplaceRestoresArchivedProfile() throws {
        var archive = DataArchive()
        archive.profile = .init(
            birthDate: Date(timeIntervalSince1970: 315_532_800),
            heightCm: 164,
            sex: BiologicalSex.female.rawValue,
            goal: FitnessGoal.fatLoss.rawValue,
            activity: ActivityBaseline.light.rawValue,
            proteinPerKgOverride: 1.8)

        let context = try makeContext()
        let current = UserProfile()
        current.birthDate = Date(timeIntervalSince1970: 631_152_000)
        current.heightCm = 191
        current.sex = .male
        current.goal = .muscleGain
        current.activity = .athlete
        current.proteinPerKgOverride = 2.2
        context.insert(current)
        try context.save()

        DataArchiveService.restore(archive, mode: .merge, context: context)

        var profiles = try context.fetch(FetchDescriptor<UserProfile>())
        #expect(profiles.count == 1)
        #expect(profiles.first?.birthDate == current.birthDate)
        #expect(profiles.first?.heightCm == 191)
        #expect(profiles.first?.sex == .male)
        #expect(profiles.first?.goal == .muscleGain)
        #expect(profiles.first?.activity == .athlete)
        #expect(profiles.first?.proteinPerKgOverride == 2.2)

        DataArchiveService.restore(archive, mode: .replace, context: context)

        profiles = try context.fetch(FetchDescriptor<UserProfile>())
        #expect(profiles.count == 1)
        #expect(profiles.first?.birthDate == archive.profile?.birthDate)
        #expect(profiles.first?.heightCm == 164)
        #expect(profiles.first?.sex == .female)
        #expect(profiles.first?.goal == .fatLoss)
        #expect(profiles.first?.activity == .light)
        #expect(profiles.first?.proteinPerKgOverride == 1.8)
    }

    /// Replace accepts version-1 archives whose optional profile is absent;
    /// it must still leave the app with an operable empty profile screen.
    @Test func replaceWithoutAnArchivedProfileCreatesAnEmptyProfile() throws {
        let context = try makeContext()
        let current = UserProfile()
        current.heightCm = 190
        context.insert(current)
        try context.save()

        DataArchiveService.restore(DataArchive(), mode: .replace, context: context)

        let profiles = try context.fetch(FetchDescriptor<UserProfile>())
        #expect(profiles.count == 1)
        #expect(profiles.first?.heightCm == 175)
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

    /// Seeding changes 1 exercise UUID between installs; both dependent IDs in
    /// an archived session and template must point at the local seeded row.
    @Test func nameDedupedExerciseReferencesUseTheSeededID() throws {
        let context = try makeContext()
        ExerciseLibrary.seedIfNeeded(context: context)
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        let local = try #require(exercises.first { $0.name == "Barbell Bench Press" })
        let archivedID = UUID()

        var archive = DataArchive()
        archive.exercises = [.init(
            id: archivedID,
            name: local.name,
            category: local.categoryRaw,
            tension: local.tensionRaw,
            bodyweightFraction: local.bodyweightFraction,
            isCustom: false,
            aliases: local.aliases)]
        archive.sessions = [.init(
            id: UUID(),
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            endedAt: nil,
            templateName: "Archived push",
            sets: [.init(order: 0, exerciseID: archivedID, weightKg: 80,
                         reps: 8, rir: 2, isWarmup: false, completedAt: nil)])]
        archive.templates = [.init(
            id: UUID(),
            name: "Archived push",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            exerciseIDs: [archivedID])]

        DataArchiveService.restore(archive, mode: .merge, context: context)

        let sessions = try context.fetch(FetchDescriptor<TrainingSession>())
        let templates = try context.fetch(FetchDescriptor<WorkoutTemplate>())
        let session = try #require(sessions.first)
        let template = try #require(templates.first)
        #expect(session.sets?.first?.exerciseID == local.id)
        #expect(template.orderedExerciseIDs == [local.id])
        #expect(!(try context.fetch(FetchDescriptor<Exercise>())).contains { $0.id == archivedID })
    }

    /// Seeding changes 1 supplement UUID between installs; its archived daily
    /// entry must follow the name-deduped local row rather than become orphaned.
    @Test func nameDedupedSupplementEntryUsesTheSeededID() throws {
        let context = try makeContext()
        SupplementCatalog.seedIfNeeded(context: context)
        let supplements = try context.fetch(FetchDescriptor<Supplement>())
        let local = try #require(supplements.first { $0.name == "Whey Protein Isolate" })
        let archivedID = UUID()

        var archive = DataArchive()
        archive.supplements = [.init(
            id: archivedID,
            name: local.name,
            category: local.categoryRaw,
            servingLabel: local.servingLabel,
            servingGrams: local.servingGrams,
            kcal: local.kcal,
            protein: local.proteinG,
            carbs: local.carbsG,
            fat: local.fatG,
            fibre: local.fibreG,
            micros: local.microsRaw,
            isCustom: false)]
        archive.supplementEntries = [.init(
            id: UUID(),
            supplementID: archivedID,
            kind: SupplementEntryKind.daily.rawValue,
            servings: 1,
            date: nil,
            startedOn: Date(timeIntervalSince1970: 1_700_000_000),
            stoppedOn: nil)]

        DataArchiveService.restore(archive, mode: .merge, context: context)

        let entries = try context.fetch(FetchDescriptor<SupplementEntry>())
        let entry = try #require(entries.first)
        #expect(entry.supplementID == local.id)
        #expect(!(try context.fetch(FetchDescriptor<Supplement>())).contains { $0.id == archivedID })
    }

    /// Two weights inside 1 archive can share a day; the mutable day index must
    /// keep the first and report exactly 1 added row plus 1 skipped duplicate.
    @Test func duplicateWeightDaysInsideOneArchiveRestoreOnce() throws {
        let day = Calendar.current.startOfDay(
            for: Date(timeIntervalSince1970: 1_700_000_000)).addingTimeInterval(3_600)
        var archive = DataArchive()
        archive.bodyMetrics = [
            .init(date: day, weightKg: 80, bodyFatPct: nil,
                  leanMassKg: nil, source: MetricSource.manual.rawValue),
            .init(date: day.addingTimeInterval(3_600), weightKg: 81,
                  bodyFatPct: nil, leanMassKg: nil, source: MetricSource.manual.rawValue),
        ]
        let context = try makeContext()

        let result = DataArchiveService.restore(archive, mode: .merge, context: context)

        let weights = try context.fetch(FetchDescriptor<BodyMetrics>())
        #expect(weights.count == 1)
        #expect(weights.first?.weightKg == 80)
        #expect(result.added == 1)
        #expect(result.skipped == 1)
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
        #expect(try context.fetch(FetchDescriptor<HydrationLog>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<HydrationSettings>()).isEmpty)
    }

}
