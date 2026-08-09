import Testing
import Foundation
import SwiftData
@testable import SuperFit

/// A health source that returns exactly what a test hands it.
private struct StubHealth: HealthProvider {
    var isAvailable = true
    var mass: [BodyMassSample] = []
    var activity: [DailyActivity] = []
    var sleepValues: [SleepSample] = []
    var rhr: [SampleValue] = []
    var hrvValues: [SampleValue] = []

    func requestAuthorization() async throws {}
    func bodyMass(in range: DateInterval) async throws -> [BodyMassSample] { mass }
    func bodyFatPercentage(in range: DateInterval) async throws -> [SampleValue] { [] }
    func leanBodyMass(in range: DateInterval) async throws -> [SampleValue] { [] }
    func dailyActivity(in range: DateInterval) async throws -> [DailyActivity] { activity }
    func workouts(in range: DateInterval) async throws -> [WorkoutSample] { [] }
    func sleep(in range: DateInterval) async throws -> [SleepSample] { sleepValues }
    func restingHeartRate(in range: DateInterval) async throws -> [SampleValue] { rhr }
    func hrv(in range: DateInterval) async throws -> [SampleValue] { hrvValues }
    func vo2Max(in range: DateInterval) async throws -> [SampleValue] { [] }
}

private struct StubRecovery: RecoveryProvider {
    var isLinked: Bool { get async { false } }
    func recoveryMetrics(in range: DateInterval) async throws -> [RecoveryMetrics] { [] }
}

@MainActor
struct SyncCoordinatorTests {

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(AppSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        return ModelContext(container)
    }

    private func rows<T: PersistentModel>(_ context: ModelContext) -> [T] {
        (try? context.fetch(FetchDescriptor<T>())) ?? []
    }

    private let cal = Calendar(identifier: .gregorian)

    /// Several readings on one day are one day's weight, not several rows.
    ///
    /// The day set used to be a snapshot taken before the loop, so it only knew
    /// about days already on disk: a smart scale writing on every step-on
    /// inserted a row per reading, and the weight list showed the day three
    /// times over.
    /// The kept reading is the lowest of the day, not the first or the last.
    /// Deliberately ordered so earliest, latest and lowest are three different
    /// readings — otherwise the test passes whichever rule is in force.
    @Test func severalReadingsOnOneDayMakeOneRowAtTheLowestWeight() async throws {
        let context = try makeContext()
        let morning = cal.date(byAdding: .hour, value: -8, to: .now)!
        let samples = [
            BodyMassSample(date: morning, kg: 80.5),                          // earliest
            BodyMassSample(date: morning.addingTimeInterval(3600), kg: 80.1),  // lowest
            BodyMassSample(date: morning.addingTimeInterval(7200), kg: 81.0),  // latest
        ]
        await SyncCoordinator(health: StubHealth(mass: samples),
                              garmin: StubRecovery(), context: context).syncAll()

        let stored: [BodyMetrics] = rows(context)
        #expect(stored.count == 1, "one row per day, not one per reading")
        #expect(stored.first?.weightKg == 80.1)
    }

    /// Order out of the source is not guaranteed, so the kept reading must not
    /// depend on it.
    @Test func theKeptReadingDoesNotDependOnSampleOrder() async throws {
        let morning = cal.date(byAdding: .hour, value: -8, to: .now)!
        let ascending = [
            BodyMassSample(date: morning, kg: 80.5),
            BodyMassSample(date: morning.addingTimeInterval(7200), kg: 80.1),
        ]
        var weights: [Double] = []
        for samples in [ascending, ascending.reversed()] {
            let context = try makeContext()
            await SyncCoordinator(health: StubHealth(mass: Array(samples)),
                                  garmin: StubRecovery(), context: context).syncAll()
            let stored: [BodyMetrics] = rows(context)
            #expect(stored.count == 1)
            weights.append(stored.first?.weightKg ?? 0)
        }
        #expect(weights[0] == weights[1])
        #expect(weights[0] == 80.1)
    }

    /// A second sync must not add the day again.
    @Test func repeatedSyncsAreIdempotent() async throws {
        let context = try makeContext()
        let health = StubHealth(mass: [BodyMassSample(date: .now.addingTimeInterval(-3600),
                                                      kg: 80)])
        let sync = SyncCoordinator(health: health, garmin: StubRecovery(), context: context)
        let first = await sync.syncAll()
        let second = await sync.syncAll()
        #expect((rows(context) as [BodyMetrics]).count == 1)
        #expect(first.weightTrendNeedsRefresh)
        #expect(first.hasChanges)
        #expect(!second.weightTrendNeedsRefresh)
        #expect(!second.hasChanges)
    }

    @Test func laterLowerWeightCorrectsTheStoredDay() async throws {
        let context = try makeContext()
        let time = Date.now.addingTimeInterval(-3600)
        await SyncCoordinator(
            health: StubHealth(mass: [BodyMassSample(date: time, kg: 82)]),
            garmin: StubRecovery(), context: context).syncAll()

        let correction = await SyncCoordinator(
            health: StubHealth(mass: [BodyMassSample(date: time.addingTimeInterval(900), kg: 80)]),
            garmin: StubRecovery(), context: context).syncAll()

        let stored: [BodyMetrics] = rows(context)
        #expect(stored.count == 1)
        #expect(stored.first?.weightKg == 80)
        #expect(correction.weightTrendNeedsRefresh)
    }

    /// Two rows already sharing a day used to trap `Dictionary(uniqueKeysWithValues:)`
    /// and crash the sync outright. Nothing in the schema prevents the duplicate —
    /// a CloudKit merge between two devices produces it — so the sync has to cope.
    @Test func duplicateDayRowsDoNotCrashTheSync() async throws {
        let context = try makeContext()
        let day = cal.startOfDay(for: .now)

        // The state a two-device merge leaves behind.
        for _ in 0..<2 {
            context.insert(DailyEnergy(date: day))
            context.insert(DailyVitals(date: day))
            let sleep = SleepData(date: day)
            sleep.asleepMinutes = 300
            context.insert(sleep)
        }
        try context.save()

        let health = StubHealth(
            activity: [DailyActivity(day: day, activeEnergyKcal: 500, basalEnergyKcal: 1600,
                                     steps: 9000, distanceKm: 7, flightsClimbed: 4)],
            sleepValues: [SleepSample(day: day, inBedMinutes: 500, asleepMinutes: 450,
                                      deepMinutes: 80, remMinutes: 100, coreMinutes: 270)],
            rhr: [SampleValue(date: day, value: 52)],
            hrvValues: [SampleValue(date: day, value: 70)])

        await SyncCoordinator(health: health, garmin: StubRecovery(),
                              context: context).syncAll()

        // Survived and physically consolidated every same-day model.
        let energy: [DailyEnergy] = rows(context)
        let vitals: [DailyVitals] = rows(context)
        let sleep: [SleepData] = rows(context)
        #expect(energy.count == 1)
        #expect(energy.first?.steps == 9000)
        #expect(vitals.count == 1)
        #expect(vitals.first?.restingHR == 52)
        #expect(sleep.count == 1)
        #expect(sleep.first?.asleepMinutes == 450)
    }
}
