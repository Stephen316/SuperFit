import Testing
import Foundation
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

    // MARK: Strength overlap

    @Test func watchStrengthOverlappingALoggedSessionIsSkipped() {
        let session = DateInterval(start: base, duration: 60 * 60)
        let decisions = WorkoutImporter.decide(
            samples: [sample("w", activity: .strengthTraining, durationMinutes: 55)],
            existingExternalIDs: [],
            loggedStrengthSessions: [session])
        #expect(decisions.first?.action == .skipLoggedStrength)
    }

    /// The watch keeps running while you rack the last set, so requiring exact
    /// containment would never match a real pair.
    @Test func partialOverlapPastHalfStillCountsAsTheSameSession() {
        let session = DateInterval(start: base, duration: 60 * 60)
        // Starts 30 min in, runs 40 min: 30 of its 40 minutes sit inside.
        let decisions = WorkoutImporter.decide(
            samples: [sample("w", activity: .strengthTraining,
                             offsetMinutes: 30, durationMinutes: 40)],
            existingExternalIDs: [],
            loggedStrengthSessions: [session])
        #expect(decisions.first?.action == .skipLoggedStrength)
    }

    @Test func aSeparateStrengthWorkoutOnTheSameDayStillImports() {
        let session = DateInterval(start: base, duration: 60 * 60)
        let decisions = WorkoutImporter.decide(
            samples: [sample("w", activity: .strengthTraining,
                             offsetMinutes: 300, durationMinutes: 45)],
            existingExternalIDs: [],
            loggedStrengthSessions: [session])
        #expect(decisions.first?.action == .insert)
    }

    /// A run happening during a logged gym session is still a run — the overlap
    /// rule is about the watch duplicating *strength* work, nothing else.
    @Test func cardioIsNeverSkippedForOverlappingAGymSession() {
        let session = DateInterval(start: base, duration: 60 * 60)
        let decisions = WorkoutImporter.decide(
            samples: [sample("r", activity: .running, durationMinutes: 55)],
            existingExternalIDs: [],
            loggedStrengthSessions: [session])
        #expect(decisions.first?.action == .insert)
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
