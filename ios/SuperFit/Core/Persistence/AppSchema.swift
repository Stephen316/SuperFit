import Foundation
import SwiftData

enum AppSchema {
    static let models: [any PersistentModel.Type] = [
        UserProfile.self, BodyMetrics.self, DailyEnergy.self,
        Food.self, NutritionLog.self, HydrationLog.self, HydrationSettings.self,
        SavedMeal.self, SavedMealItem.self,
        Exercise.self, TrainingSession.self, SetEntry.self, WorkoutRecord.self,
        WorkoutTemplate.self, WorkoutTemplateItem.self,
        SleepData.self, DailyVitals.self,
        RecoveryScoreRecord.self, MetabolicEstimateRecord.self,
        StrainRecord.self,
        CyclicalPatternRecord.self,
        Supplement.self, SupplementEntry.self
    ]

    /// True when persistence failed and the app is running on a throwaway
    /// in-memory store. The UI warns rather than silently discarding data.
    private(set) nonisolated(unsafe) static var isEphemeral = false

    /// CloudKit must only be opened by a build whose provisioning profile carries
    /// the capability. Personal-team builds deliberately omit it; attempting the
    /// automatic configuration anyway performs a failing schema check before the
    /// first frame. Paid/distribution builds opt in with the
    /// `SUPERFIT_CLOUDKIT` Swift compilation condition alongside their entitlement.
    private static var cloudKitEnabled: Bool {
        #if SUPERFIT_CLOUDKIT
        true
        #else
        false
        #endif
    }

    /// Offline-first local store with transparent CloudKit sync to the user's
    /// private database, degrading in three steps:
    ///
    /// 1. CloudKit-backed — the normal path.
    /// 2. Local-only — no iCloud account, or CloudKit unavailable.
    /// 3. In-memory — the on-disk store itself can't open (corrupt file,
    ///    incompatible migration, no space). Previously this step was `try!`,
    ///    which turned a recoverable disk problem into a launch crash with no
    ///    route back: a user who couldn't open the app couldn't clear the bad
    ///    store either. Losing this session's data is bad; a permanently
    ///    unlaunchable app is worse.
    static func makeContainer() -> ModelContainer {
        let schema = Schema(models)

        if cloudKitEnabled {
            if let cloud = try? ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)]) {
                return cloud
            }
        }
        if let local = try? ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, cloudKitDatabase: .none)]) {
            return local
        }

        isEphemeral = true
        // An in-memory store is built from the same schema with no file to
        // conflict with, so this only fails if the schema itself is invalid —
        // a programmer error that should surface loudly in development.
        do {
            return try ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        } catch {
            fatalError("SuperFit schema is invalid and cannot be loaded: \(error)")
        }
    }
}
