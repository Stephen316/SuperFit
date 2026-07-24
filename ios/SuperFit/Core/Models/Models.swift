import Foundation
import SwiftData

// CloudKit constraints: every relationship optional, every scalar defaulted,
// no unique constraints (dedupe on natural keys in code).

enum MetricSource: String, Codable, Sendable { case manual, healthKit }
enum MealSlot: String, Codable, CaseIterable, Sendable { case breakfast, lunch, dinner, snack }
enum FoodSource: String, Codable, Sendable { case openFoodFacts, usda, custom }
enum MuscleGroup: String, Codable, CaseIterable, Sendable {
    case chest, back, lowerBack, traps, shoulders, biceps, triceps, forearms
    case quads, hamstrings, glutes, calves, core

    var displayName: String {
        switch self {
        case .lowerBack: return "Lower back"
        default: return rawValue.capitalized
        }
    }
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
    /// Muscle tension map, "muscle:score" with score 1–5 (5 = prime mover under
    /// maximal tension, 1 = lightly involved). CloudKit-safe string encoding.
    var tensionRaw: [String] = []
    var categoryRaw: String = ExerciseCategory.barbell.rawValue
    var isCustom: Bool = false

    init(name: String, category: ExerciseCategory, tension: [MuscleGroup: Int], isCustom: Bool = false) {
        self.name = name
        self.categoryRaw = category.rawValue
        self.isCustom = isCustom
        self.tension = tension
    }

    var tension: [MuscleGroup: Int] {
        get {
            var out: [MuscleGroup: Int] = [:]
            for entry in tensionRaw {
                let parts = entry.split(separator: ":")
                guard parts.count == 2, let m = MuscleGroup(rawValue: String(parts[0])),
                      let s = Int(parts[1]) else { continue }
                out[m] = s.clamped(to: 1...5)
            }
            return out
        }
        set {
            tensionRaw = newValue
                .filter { $0.value > 0 }
                .sorted { $0.value > $1.value }
                .map { "\($0.key.rawValue):\($0.value.clamped(to: 1...5))" }
        }
    }

    var primaryMuscle: MuscleGroup {
        tension.max { $0.value < $1.value }?.key ?? .core
    }
}

/// User-saved reusable workout (built-ins live in ExerciseLibrary.templates).
@Model
final class WorkoutTemplate {
    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date()
    @Relationship(deleteRule: .cascade) var items: [WorkoutTemplateItem]? = []

    init(name: String) { self.name = name }

    var orderedExerciseIDs: [UUID] {
        (items ?? []).sorted { $0.order < $1.order }.compactMap(\.exerciseID)
    }
}

@Model
final class WorkoutTemplateItem {
    var order: Int = 0
    var exerciseID: UUID?
    var template: WorkoutTemplate?

    init(order: Int, exerciseID: UUID) {
        self.order = order
        self.exerciseID = exerciseID
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
    var restSeconds: Int?
    var completedAt: Date?
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

/// One row per day of heart metrics — the recovery engine's baseline inputs.
@Model
final class DailyVitals {
    var date: Date = Date()
    var restingHR: Double?
    var hrvSDNN: Double?

    init(date: Date) { self.date = date }
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
