import Testing
import Foundation
import SwiftData
@testable import SuperFit

/// The import rules exist to stop the same workout appearing twice, from two
/// different directions: the observer query re-firing, and the watch recording a
/// gym session the app already logged set by set.
struct WorkoutImportTests {

    private let base = Date(timeIntervalSince1970: 1_750_000_000)

    private func sample(_ id: String, activity: WorkoutActivity = .running,
                        offsetMinutes: Double = 0,
                        durationMinutes: Double = 45) -> WorkoutSample {
        let start = base.addingTimeInterval(offsetMinutes * 60)
        return WorkoutSample(externalID: id,
                             start: start,
                             end: start.addingTimeInterval(durationMinutes * 60),
                             activity: activity,
                             activeEnergyKcal: 400)
    }

    @MainActor
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(AppSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        return ModelContext(container)
    }

    // MARK: Idempotency

    @Test func firstImportInsertsEverything() {
        let decisions = WorkoutImporter.decide(
            samples: [sample("a"), sample("b", offsetMinutes: 120)],
            existingExternalIDs: [])
        #expect(decisions.map(\.action) == [.insert, .insert])
    }

    /// HKObserverQuery fires on every change to the workout store, not once per
    /// new workout, so this is the common path rather than an edge case.
    @Test func reimportingUpdatesRatherThanDuplicating() {
        let decisions = WorkoutImporter.decide(
            samples: [sample("a"), sample("b", offsetMinutes: 120)],
            existingExternalIDs: ["a", "b"])
        #expect(decisions.allSatisfy { $0.action == .update })
    }

    @Test func aRepeatedIDWithinOneBatchIsSkipped() {
        let decisions = WorkoutImporter.decide(
            samples: [sample("a"), sample("a")],
            existingExternalIDs: [])
        #expect(decisions.map(\.action) == [.insert, .skipDuplicateInBatch])
    }

    /// SuperFit now writes its own workouts to HealthKit; those come back through
    /// the observer authored by this app. Re-importing them would duplicate a
    /// session already stored, so the sync must drop anything it authored while
    /// still importing genuine watch/third-party workouts.
    @MainActor
    @Test func workoutsAuthoredBySuperFitAreNotReimported() throws {
        let context = try makeContext()
        let service = WorkoutSyncService(garmin: nil, context: context)

        var ours = sample("ours")
        ours.sourceBundleID = Bundle.main.bundleIdentifier
        var watch = sample("watch", offsetMinutes: 120)
        watch.sourceBundleID = "com.apple.health"

        let inserted = service.apply([ours, watch])

        let records = try context.fetch(FetchDescriptor<WorkoutRecord>())
        #expect(inserted == 1)
        #expect(records.count == 1)
        #expect(records.first?.externalID == "watch")
    }

    // MARK: Time-based reconciliation

    @Test func watchStrengthOverlappingALoggedSessionIsRetainedForMerging() {
        let session = DateInterval(start: base, duration: 60 * 60)
        let decisions = WorkoutImporter.decide(
            samples: [sample("w", activity: .strengthTraining, durationMinutes: 55)],
            existingExternalIDs: [])
        #expect(decisions.first?.action == .insert)

        let workout = DateInterval(start: base, duration: 55 * 60)
        #expect(WorkoutTimeMatcher.matches(workouts: [workout], sessions: [session]) == [0: 0])
    }

    /// The watch keeps running while you rack the last set, so requiring exact
    /// containment would never match a real pair.
    @Test func partialOverlapPastHalfStillCountsAsTheSameSession() {
        let session = DateInterval(start: base, duration: 60 * 60)
        // Starts 30 min in, runs 40 min: 30 of its 40 minutes sit inside.
        let workout = DateInterval(start: base.addingTimeInterval(30 * 60),
                                   duration: 40 * 60)
        #expect(WorkoutTimeMatcher.matches(workouts: [workout], sessions: [session]) == [0: 0])
    }

    @Test func aSeparateStrengthWorkoutOnTheSameDayStillImports() {
        let session = DateInterval(start: base, duration: 60 * 60)
        let workout = DateInterval(start: base.addingTimeInterval(300 * 60),
                                   duration: 45 * 60)
        #expect(WorkoutTimeMatcher.matches(workouts: [workout], sessions: [session]).isEmpty)
    }

    @Test func oneWatchWorkoutCannotAttachToTwoPhoneSessions() {
        let workout = DateInterval(start: base, duration: 90 * 60)
        let sessions = [
            DateInterval(start: base, duration: 45 * 60),
            DateInterval(start: base.addingTimeInterval(45 * 60), duration: 45 * 60)
        ]
        let matches = WorkoutTimeMatcher.matches(workouts: [workout], sessions: sessions)
        #expect(matches.count == 1)
        #expect(matches[0] == 0)
    }

    @Test @MainActor
    func watchAndIPhoneCardioBecomeOneRecordByTime() throws {
        let context = try makeContext()
        let phone = WorkoutRecord(startedAt: base.addingTimeInterval(2 * 60),
                                  endedAt: base.addingTimeInterval(47 * 60),
                                  activity: .running, source: .liveSession)
        phone.sourceName = "iPhone"
        phone.distanceMetres = 7_800
        phone.sessionRPE = 8
        context.insert(phone)

        var watch = sample("watch-run", activity: .running, durationMinutes: 50)
        watch.sourceName = "Apple Watch"
        watch.avgHeartRate = 156
        watch.maxHeartRate = 181
        watch.heartRateSegments = [.init(durationMinutes: 50, avgHeartRate: 156)]
        WorkoutSyncService(context: context).apply([watch])

        let stored = try context.fetch(FetchDescriptor<WorkoutRecord>())
        #expect(stored.count == 1)
        #expect(stored.first?.externalID == "watch-run")
        #expect(stored.first?.source == .liveSession)
        #expect(stored.first?.sessionRPE == 8)
        #expect(stored.first?.distanceMetres == 7_800)
        #expect(stored.first?.avgHeartRate == 156)
        #expect(stored.first?.heartRateSegments.count == 1)
        #expect(stored.first?.sourceName == "iPhone + Apple Watch")
    }

    @Test @MainActor
    func nonOverlappingCardioRemainsTwoWorkouts() throws {
        let context = try makeContext()
        let phone = WorkoutRecord(startedAt: base,
                                  endedAt: base.addingTimeInterval(45 * 60),
                                  activity: .running, source: .liveSession)
        context.insert(phone)

        WorkoutSyncService(context: context).apply([
            sample("later-run", activity: .running, offsetMinutes: 180)
        ])

        let stored = try context.fetch(FetchDescriptor<WorkoutRecord>())
        #expect(stored.count == 2)
    }

    @Test @MainActor
    func existingWatchCopyIsConsolidatedWhenPhoneWorkoutAppearsLater() throws {
        let context = try makeContext()
        let imported = WorkoutRecord(startedAt: base,
                                     endedAt: base.addingTimeInterval(50 * 60),
                                     activity: .running, source: .appleHealth)
        imported.externalID = "watch-run"
        imported.avgHeartRate = 154
        context.insert(imported)

        let phone = WorkoutRecord(startedAt: base.addingTimeInterval(2 * 60),
                                  endedAt: base.addingTimeInterval(48 * 60),
                                  activity: .running, source: .liveSession)
        phone.sessionRPE = 7
        context.insert(phone)

        var refreshedWatch = sample("watch-run", activity: .running, durationMinutes: 50)
        refreshedWatch.avgHeartRate = 156
        WorkoutSyncService(context: context).apply([refreshedWatch])

        let stored = try context.fetch(FetchDescriptor<WorkoutRecord>())
        #expect(stored.count == 1)
        #expect(stored.first?.source == .liveSession)
        #expect(stored.first?.externalID == "watch-run")
        #expect(stored.first?.sessionRPE == 7)
        #expect(stored.first?.avgHeartRate == 156)
    }

    // MARK: Activity taxonomy

    @Test func everyActivityHasADistinctNameAndASymbol() {
        let names = Set(WorkoutActivity.allCases.map(\.displayName))
        #expect(names.count == WorkoutActivity.allCases.count)
        #expect(WorkoutActivity.allCases.allSatisfy { !$0.symbolName.isEmpty })
    }

    @Test func everyActivityBelongsToExactlyOneGroup() {
        let grouped = WorkoutActivity.Group.allCases
            .flatMap { WorkoutActivity.inGroup($0) }
        #expect(Set(grouped) == Set(WorkoutActivity.allCases))
        #expect(grouped.count == WorkoutActivity.allCases.count)
    }

    /// The metrics set drives which rows the detail view shows, so a swim
    /// claiming elevation would print "0 m climbed" as though it were measured.
    @Test func metricsMatchTheActivity() {
        #expect(WorkoutActivity.poolSwimming.metrics.contains(.strokes))
        #expect(!WorkoutActivity.poolSwimming.metrics.contains(.elevation))
        #expect(WorkoutActivity.treadmillRunning.metrics.contains(.distance))
        #expect(!WorkoutActivity.treadmillRunning.metrics.contains(.elevation))
        #expect(WorkoutActivity.trailRunning.metrics.contains(.elevation))
        #expect(WorkoutActivity.yoga.metrics.isEmpty)
    }

    @Test func onlyStrengthActivitiesLogSets() {
        for activity in WorkoutActivity.allCases {
            #expect(activity.isStrength == activity.metrics.contains(.sets),
                    "\(activity.rawValue) disagrees about being strength work")
        }
    }

    @Test func indoorActivitiesDoNotAskForLocation() {
        #expect(!WorkoutActivity.treadmillRunning.usesLocation)
        #expect(!WorkoutActivity.indoorCycling.usesLocation)
        #expect(!WorkoutActivity.indoorRowing.usesLocation)
        #expect(!WorkoutActivity.poolSwimming.usesLocation)
        #expect(WorkoutActivity.running.usesLocation)
        #expect(WorkoutActivity.cycling.usesLocation)
    }

    // MARK: Garmin mapping

    @Test func garminActivityKeysMapOntoTheTaxonomy() {
        #expect(GarminWorkoutDTO.activity(for: "trail_running") == .trailRunning)
        #expect(GarminWorkoutDTO.activity(for: "lap_swimming") == .poolSwimming)
        #expect(GarminWorkoutDTO.activity(for: "INDOOR_CYCLING") == .indoorCycling)
    }

    /// A Garmin activity type this build has never heard of must still import.
    @Test func unknownGarminKeysFallBackRatherThanFailing() {
        #expect(GarminWorkoutDTO.activity(for: "underwater_hockey") == .other)
    }

    @Test func trainingEffectSummarisesWhicheverHalvesArePresent() {
        #expect(GarminWorkoutDTO.effectSummary(aerobic: 3.4, anaerobic: 1.2)
                == "Aerobic 3.4 · anaerobic 1.2")
        #expect(GarminWorkoutDTO.effectSummary(aerobic: 3.4, anaerobic: nil)
                == "Aerobic 3.4")
        #expect(GarminWorkoutDTO.effectSummary(aerobic: nil, anaerobic: nil) == nil)
    }

    // MARK: Garmin link safety

    /// A session token belongs to exactly 1 backend: saving the same URL keeps
    /// it, while changing to a second URL must clear it before any API request.
    @Test func changingGarminBackendClearsOnlyTheOldBackendsToken() {
        let originalURL = URL(string: "https://garmin-one.example.com")!
        let replacementURL = URL(string: "https://garmin-two.example.com")!
        let linked = GarminProvider.Config(baseURL: originalURL,
                                           sessionToken: "backend-one-token")

        #expect(linked.settingBackend(originalURL).sessionToken == "backend-one-token")
        #expect(linked.settingBackend(replacementURL).sessionToken == nil)
    }

    /// The callback window is at most 600 seconds and exactly 1 use; this keeps
    /// an unsolicited or replayed deep link from creating a linked session.
    @Test func pendingGarminLinkIsShortLivedAndSingleUse() {
        let suiteName = "GarminConfigStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let startedAt = Date(timeIntervalSince1970: 1_750_000_000)

        GarminConfigStore.beginLinking(at: startedAt, defaults: defaults)
        #expect(GarminConfigStore.consumePendingLink(
            at: startedAt.addingTimeInterval(600), defaults: defaults))
        #expect(!GarminConfigStore.consumePendingLink(
            at: startedAt.addingTimeInterval(600), defaults: defaults))

        GarminConfigStore.beginLinking(at: startedAt, defaults: defaults)
        #expect(!GarminConfigStore.consumePendingLink(
            at: startedAt.addingTimeInterval(601), defaults: defaults))
    }
}
