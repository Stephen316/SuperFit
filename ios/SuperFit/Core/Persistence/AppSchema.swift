import Foundation
import SwiftData

enum AppSchema {
    static let models: [any PersistentModel.Type] = [
        UserProfile.self, BodyMetrics.self, DailyEnergy.self,
        Food.self, NutritionLog.self, DayLogStatus.self,
        SavedMeal.self, SavedMealItem.self,
        Exercise.self, TrainingSession.self, SetEntry.self,
        SleepData.self, RecoveryScoreRecord.self, MetabolicEstimateRecord.self
    ]

    /// Offline-first local store with transparent CloudKit sync to the user's
    /// private database. Falls back to a local-only store if CloudKit is
    /// unavailable (e.g. not signed into iCloud) so the app still works offline.
    static func makeContainer() -> ModelContainer {
        let schema = Schema(models)
        do {
            let config = ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            let local = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
            return try! ModelContainer(for: schema, configurations: [local])
        }
    }
}
