import Foundation
import SwiftData

// CloudKit constraints: every relationship optional, every scalar defaulted,
// no unique constraints (dedupe on natural keys in code).

enum MetricSource: String, Codable, Sendable { case manual, healthKit }
enum MealSlot: String, Codable, CaseIterable, Sendable { case breakfast, lunch, dinner, snack }
enum FoodSource: String, Codable, Sendable { case openFoodFacts, usda, custom }
enum MuscleGroup: String, Codable, CaseIterable, Sendable {
    case chest, back, quads, hamstrings, glutes, shoulders, biceps, triceps, calves, core
}
enum ExerciseCategory: String, Codable, Sendable { case barbell, dumbbell, machine, cable, bodyweight }

@Model
final class UserProfile {
    var id: UUID = UUID()
    var birthDate: Date = Date(timeIntervalSince1970: 0)
    var sexRaw: String = BiologicalSex.other.rawValue
    var heightCm: Double = 175
    var goalRaw: String = FitnessGoal.recomposition.rawValue
    var activityRaw: String = ActivityBaseline.moderate.rawValue
    var proteinPerKgOverride: Double = 0     // 0 = use goal default
    var usesMetric: Bool = true

    init() {}

    var sex: BiologicalSex { get { .init(rawValue: sexRaw) ?? .other } set { sexRaw = newValue.rawValue } }
    var goal: FitnessGoal { get { .init(rawValue: goalRaw) ?? .recomposition } set { goalRaw = newValue.rawValue } }
    var activity: ActivityBaseline { get { .init(rawValue: activityRaw) ?? .moderate } set { activityRaw = newValue.rawValue } }

    var ageYears: Double {
        Calendar.current.dateComponents([.day], from: birthDate, to: .now).day.map { Double($0) / 365.25 } ?? 30
    }
}

@Model
final class BodyMetrics {
    var date: Date = Date()
    var weightKg: Double = 0
    var trendWeightKg: Double?
    var bodyFatPct: Double?
    var leanMassKg: Double?
    var sourceRaw: String = MetricSource.manual.rawValue

    init(date: Date, weightKg: Double, source: MetricSource = .manual) {
        self.date = date
        self.weightKg = weightKg
        self.sourceRaw = source.rawValue
    }
}

@Model
final class DailyEnergy {
    var date: Date = Date()
    var activeEnergyKcal: Double = 0
    var basalEnergyKcal: Double = 0
    var steps: Int = 0
    var distanceKm: Double = 0
    var flightsClimbed: Int = 0

    init(date: Date) { self.date = date }
}

@Model
final class Food {
    var id: UUID = UUID()
    var sourceRaw: String = FoodSource.custom.rawValue
    var remoteID: String?                 // barcode / FDC id — dedupe key
    var name: String = ""
    var brand: String?
    var kcalPer100g: Double = 0
    var proteinPer100g: Double = 0
    var carbsPer100g: Double = 0
    var fatPer100g: Double = 0
    var fibrePer100g: Double = 0
    var microsJSON: Data?                  // [String: Double] per 100 g
    var isFavorite: Bool = false

    init(name: String, source: FoodSource = .custom) {
        self.name = name
        self.sourceRaw = source.rawValue
    }
}

@Model
final class NutritionLog {
    var date: Date = Date()                // day key
    var loggedAt: Date = Date()
    var foodID: UUID?
    var foodName: String?                  // display snapshot
    var servingGrams: Double = 0
    var kcal: Double = 0                    // snapshotted at log time
    var proteinG: Double = 0
    var carbsG: Double = 0
    var fatG: Double = 0
    var fibreG: Double = 0
    var mealRaw: String = MealSlot.snack.rawValue

    init(date: Date, meal: MealSlot) {
        self.date = date
        self.mealRaw = meal.rawValue
    }
}

/// Per-day logging status. Only days explicitly marked complete feed the
/// metabolism engine's intake average — prevents the partial-day bias found in
/// validation (see docs/ALGORITHMS.md "Known limitation").
@Model
final class DayLogStatus {
    var date: Date = Date()
    var loggingComplete: Bool = false

    init(date: Date, loggingComplete: Bool = false) {
        self.date = date
        self.loggingComplete = loggingComplete
    }
}

/// Named meal template: re-log a whole meal in one tap.
@Model
final class SavedMeal {
    var id: UUID = UUID()
    var name: String = ""
    @Relationship(deleteRule: .cascade) var items: [SavedMealItem]? = []

    init(name: String) { self.name = name }
}

@Model
final class SavedMealItem {
    var foodID: UUID?
    var servingGrams: Double = 0
    var meal: SavedMeal?

    init(foodID: UUID, servingGrams: Double) {
        self.foodID = foodID
        self.servingGrams = servingGrams
    }
}

@Model
final class Exercise {
    var id: UUID = UUID()
    var name: String = ""
    var primaryMuscleRaw: String = MuscleGroup.chest.rawValue
    var secondaryMusclesRaw: [String] = []
    var categoryRaw: String = ExerciseCategory.barbell.rawValue

    init(name: String, primary: MuscleGroup, category: ExerciseCategory) {
        self.name = name
        self.primaryMuscleRaw = primary.rawValue
        self.categoryRaw = category.rawValue
    }
}

@Model
final class TrainingSession {
    var id: UUID = UUID()
    var startedAt: Date = Date()
    var endedAt: Date?
    var templateName: String?
    var bodyweightSnapshotKg: Double?
    @Relationship(deleteRule: .cascade) var sets: [SetEntry]? = []

    init(startedAt: Date = .now, templateName: String? = nil) {
        self.startedAt = startedAt
        self.templateName = templateName
    }
}

@Model
final class SetEntry {
    var order: Int = 0
    var exerciseID: UUID?
    var weightKg: Double = 0
    var reps: Int = 0
    var rir: Int?
    var isWarmup: Bool = false
    var session: TrainingSession?

    init(order: Int, exerciseID: UUID, weightKg: Double, reps: Int) {
        self.order = order
        self.exerciseID = exerciseID
        self.weightKg = weightKg
        self.reps = reps
    }

    var volumeKg: Double { isWarmup ? 0 : weightKg * Double(reps) }
}

@Model
final class SleepData {
    var date: Date = Date()                // wake day
    var inBedMinutes: Int = 0
    var asleepMinutes: Int = 0
    var deepMinutes: Int = 0
    var remMinutes: Int = 0
    var coreMinutes: Int = 0

    init(date: Date) { self.date = date }

    var efficiency: Double { inBedMinutes == 0 ? 0 : Double(asleepMinutes) / Double(inBedMinutes) }
}

@Model
final class RecoveryScoreRecord {
    var date: Date = Date()
    var score: Double = 0
    var recommendationRaw: String = ""
    init(date: Date, score: Double, recommendation: String) {
        self.date = date; self.score = score; self.recommendationRaw = recommendation
    }
}

@Model
final class MetabolicEstimateRecord {
    var date: Date = Date()
    var tdeeKcal: Double = 0
    var windowDays: Int = 30
    var confidence: Double = 0
    var trendSlopeKgPerWeek: Double = 0
    var avgIntakeKcal: Double = 0
    init(date: Date, window: Int) { self.date = date; self.windowDays = window }
}
