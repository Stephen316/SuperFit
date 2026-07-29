import Foundation
import SwiftData

// CloudKit constraints: every relationship optional, every scalar defaulted,
// no unique constraints (dedupe on natural keys in code).

enum MetricSource: String, Codable, Sendable { case manual, healthKit }
enum MealSlot: String, Codable, CaseIterable, Sendable { case breakfast, lunch, dinner, snack }
enum FoodSource: String, Codable, Sendable { case openFoodFacts, usda, custom, supplement }
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

    /// Weight to drive targets from. The smoothed trend where available:
    /// a single reading carries 1–2 kg of water noise, and letting that move
    /// the day's calorie and protein targets makes them jitter for no reason.
    var basisWeightKg: Double { trendWeightKg ?? weightKg }

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
    /// USDA household measures, JSON [FoodPortion]. Cached so a food logged
    /// once keeps its "1 medium" option offline and without a second request.
    var portionsJSON: Data?
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
    /// Micronutrients snapshotted at log time, "key:amount" (CloudKit-safe).
    /// Absent keys mean the source had no value — not zero.
    var microsRaw: [String] = []

    init(date: Date, meal: MealSlot) {
        self.date = date
        self.mealRaw = meal.rawValue
    }

    var micros: [Micronutrient: Double] {
        get {
            var out: [Micronutrient: Double] = [:]
            for entry in microsRaw {
                let parts = entry.split(separator: ":")
                guard parts.count == 2, let m = Micronutrient(rawValue: String(parts[0])),
                      let v = Double(parts[1]) else { continue }
                out[m] = v
            }
            return out
        }
        set {
            microsRaw = newValue.map { "\($0.key.rawValue):\(($0.value * 1000).rounded() / 1000)" }
        }
    }
}

enum SupplementCategory: String, Codable, CaseIterable, Sendable {
    case protein, vitamins, minerals, performance, health

    var displayName: String {
        switch self {
        case .protein: return "Protein and amino acids"
        case .vitamins: return "Vitamins"
        case .minerals: return "Minerals and electrolytes"
        case .performance: return "Performance"
        case .health: return "General health"
        }
    }
}

/// A supplement and what one serving contributes. Seeded from
/// `SupplementCatalog`; users can add their own.
@Model
final class Supplement {
    var id: UUID = UUID()
    var name: String = ""
    var categoryRaw: String = SupplementCategory.health.rawValue
    /// e.g. "capsule", "5 g scoop", "30 g scoop" — shown next to the count.
    var servingLabel: String = "serving"
    /// Mass of one serving, when it has one. Nil for capsules and tablets.
    var servingGrams: Double?
    var kcal: Double = 0
    var proteinG: Double = 0
    var carbsG: Double = 0
    var fatG: Double = 0
    var fibreG: Double = 0
    /// Micronutrients per serving, "key:amount" (CloudKit-safe, as elsewhere).
    var microsRaw: [String] = []
    var isCustom: Bool = false

    init(name: String, category: SupplementCategory, servingLabel: String,
         servingGrams: Double? = nil,
         profile: NutrientProfile = NutrientProfile(), isCustom: Bool = false) {
        self.name = name
        self.categoryRaw = category.rawValue
        self.servingLabel = servingLabel
        self.servingGrams = servingGrams
        self.isCustom = isCustom
        self.kcal = profile.kcal
        self.proteinG = profile.proteinG
        self.carbsG = profile.carbsG
        self.fatG = profile.fatG
        self.fibreG = profile.fibreG
        self.microsRaw = profile.micros.map { "\($0.key):\($0.value)" }
    }

    var category: SupplementCategory {
        SupplementCategory(rawValue: categoryRaw) ?? .health
    }

    /// Whether this also belongs in the food diary. A protein bar is a snack by
    /// any reasonable reading; a vitamin D capsule is not. Needs both a serving
    /// weight and calories, so 0 kcal powders like creatine stay out of food
    /// search where they'd only be noise.
    var isFoodLike: Bool { (servingGrams ?? 0) > 0 && kcal > 0 }

    var perServing: NutrientProfile {
        var micros: [String: Double] = [:]
        for entry in microsRaw {
            let parts = entry.split(separator: ":")
            guard parts.count == 2, let v = Double(parts[1]) else { continue }
            micros[String(parts[0])] = v
        }
        return NutrientProfile(kcal: kcal, proteinG: proteinG, carbsG: carbsG,
                               fatG: fatG, fibreG: fibreG, micros: micros)
    }
}

/// How a supplement applies to a day.
///
/// One model covers three roles so a daily supplement needs no row per day —
/// materialising a year of creatine would be 365 rows saying the same thing.
/// A `.daily` entry stands until stopped; `.once` and `.skipped` are the
/// exceptions layered over it.
enum SupplementEntryKind: String, Codable, Sendable {
    case once      // taken on `date` only
    case daily     // taken every day from `startedOn` until `stoppedOn`
    case skipped   // a daily supplement deliberately not taken on `date`
}

@Model
final class SupplementEntry {
    var id: UUID = UUID()
    var supplementID: UUID?
    var kindRaw: String = SupplementEntryKind.once.rawValue
    var servings: Double = 1
    /// Set for `.once` and `.skipped`.
    var date: Date?
    /// Set for `.daily`. `stoppedOn` nil means still running.
    var startedOn: Date?
    var stoppedOn: Date?

    init(supplementID: UUID, kind: SupplementEntryKind, servings: Double = 1) {
        self.supplementID = supplementID
        self.kindRaw = kind.rawValue
        self.servings = servings
    }

    var kind: SupplementEntryKind {
        SupplementEntryKind(rawValue: kindRaw) ?? .once
    }

    /// Whether a `.daily` entry is in force on `day`.
    func covers(_ day: Date, calendar: Calendar = .current) -> Bool {
        guard kind == .daily, let startedOn else { return false }
        let d = calendar.startOfDay(for: day)
        if d < calendar.startOfDay(for: startedOn) { return false }
        if let stoppedOn, d > calendar.startOfDay(for: stoppedOn) { return false }
        return true
    }
}

/// Named meal template: re-log a whole meal in one tap.
@Model
final class SavedMeal {
    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date()
    var lastLoggedAt: Date?
    @Relationship(deleteRule: .cascade) var items: [SavedMealItem]? = []

    init(name: String) { self.name = name }

    var orderedItems: [SavedMealItem] {
        (items ?? []).sorted { $0.addedAt < $1.addedAt }
    }
}

@Model
final class SavedMealItem {
    var id: UUID = UUID()
    var foodID: UUID?
    /// Display snapshot, so a meal still reads sensibly if the food it points
    /// at is later deleted from the food list.
    var foodName: String?
    var servingGrams: Double = 0
    var addedAt: Date = Date()
    var meal: SavedMeal?

    init(foodID: UUID, servingGrams: Double, foodName: String? = nil) {
        self.foodID = foodID
        self.servingGrams = servingGrams
        self.foodName = foodName
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
    /// Share of bodyweight moved (0 for externally loaded lifts). Feeds training
    /// load so unweighted work isn't scored as zero effort.
    var bodyweightFraction: Double = 0

    init(name: String, category: ExerciseCategory, tension: [MuscleGroup: Int],
         bodyweightFraction: Double = 0, isCustom: Bool = false) {
        self.name = name
        self.categoryRaw = category.rawValue
        self.isCustom = isCustom
        self.bodyweightFraction = bodyweightFraction
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

enum WorkoutSource: String, Codable, Sendable {
    case appleHealth, garmin, manual, liveSession

    var displayName: String {
        switch self {
        case .appleHealth: return "Apple Health"
        case .garmin: return "Garmin"
        case .manual: return "Manual entry"
        case .liveSession: return "Tracked in SuperFit"
        }
    }
}

/// A non-strength workout — a run, ride, swim, class — imported from a watch or
/// tracked in the app.
///
/// Kept separate from `TrainingSession` rather than bolted onto it: a session is
/// a list of sets against the exercise catalog, and forcing a 10 km run into that
/// shape would mean a set with no exercise, no weight and no reps. They share the
/// history view, not the schema.
///
/// `externalID` is the source's own identifier (HealthKit's workout UUID), which
/// is what makes repeated imports idempotent — the observer query fires on every
/// change to the workout store, not once per new workout.
@Model
final class WorkoutRecord {
    var id: UUID = UUID()
    var externalID: String?
    var startedAt: Date = Date()
    var endedAt: Date = Date()
    var activityRaw: String = WorkoutActivity.other.rawValue
    var sourceRaw: String = WorkoutSource.appleHealth.rawValue
    var sourceName: String?

    var activeEnergyKcal: Double = 0
    var totalEnergyKcal: Double?
    var distanceMetres: Double?
    var avgHeartRate: Double?
    var maxHeartRate: Double?
    var minHeartRate: Double?
    var elevationGainMetres: Double?
    var avgCadence: Double?
    var avgPowerWatts: Double?
    var swimStrokeCount: Double?
    var swimStrokeStyle: String?
    /// Laps as JSON — a handful of values per lap, only ever read as a whole,
    /// and a relationship would add a CloudKit-synced table for no query benefit.
    var lapsJSON: Data?
    var notes: String?

    init(startedAt: Date = .now, endedAt: Date = .now,
         activity: WorkoutActivity = .other, source: WorkoutSource = .manual) {
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.activityRaw = activity.rawValue
        self.sourceRaw = source.rawValue
    }

    var activity: WorkoutActivity {
        get { WorkoutActivity(rawValue: activityRaw) ?? .other }
        set { activityRaw = newValue.rawValue }
    }

    var source: WorkoutSource {
        get { WorkoutSource(rawValue: sourceRaw) ?? .appleHealth }
        set { sourceRaw = newValue.rawValue }
    }

    var laps: [WorkoutLapSample] {
        get { lapsJSON.flatMap { try? JSONDecoder().decode([WorkoutLapSample].self, from: $0) } ?? [] }
        set { lapsJSON = newValue.isEmpty ? nil : try? JSONEncoder().encode(newValue) }
    }

    var durationSeconds: Double { endedAt.timeIntervalSince(startedAt) }

    /// Metres per second, or nil when the activity carries no distance. Guarded
    /// on duration as well: a zero-length workout would divide by zero.
    var averageSpeed: Double? {
        guard let distanceMetres, distanceMetres > 0, durationSeconds > 0 else { return nil }
        return distanceMetres / durationSeconds
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
    /// Clock times of the main sleep block. Nil for rows synced before these
    /// were captured; they backfill on the next 90-day sync.
    var bedtime: Date?
    var wakeTime: Date?

    init(date: Date) { self.date = date }

    /// Nil when time-in-bed is unknown. Must not collapse to 0 — the recovery
    /// engine treats a present value as measured, so a false 0 would read as
    /// "awake all night" and strip 30% off the sleep component.
    var efficiency: Double? {
        inBedMinutes > 0 ? Double(asleepMinutes) / Double(inBedMinutes) : nil
    }

    /// Staged data only exists when a watch was worn; phone-only sleep has none.
    var hasStages: Bool { deepMinutes + remMinutes + coreMinutes > 0 }
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
    /// Fraction of the four inputs (sleep/HRV/RHR/load) that were available.
    /// 0 means the score is the neutral 50 fallback, not a real reading.
    var dataCompleteness: Double = 0

    init(date: Date, score: Double, recommendation: String) {
        self.date = date; self.score = score; self.recommendationRaw = recommendation
    }
}

/// Internal flag: a recurring multi-week rhythm found in a recovery marker.
/// Stays on-device like everything else; it exists so the baseline can be
/// levelled, and so the detection is inspectable rather than invisible magic.
@Model
final class CyclicalPatternRecord {
    /// "hrv" or "restingHR" — which marker the rhythm was found in.
    var markerRaw: String = ""
    var detectedAt: Date = Date()
    var periodDays: Int = 0
    var cyclesObserved: Int = 0
    var strength: Double = 0
    var amplitude: Double = 0
    /// Per-phase offsets, index = phase position.
    var profile: [Double] = []
    /// False once the evidence bar stops being met; kept rather than deleted so
    /// a pattern that comes and goes doesn't silently churn.
    var isActive: Bool = true

    init(marker: String) { self.markerRaw = marker }
}

@Model
final class MetabolicEstimateRecord {
    var date: Date = Date()
    var tdeeKcal: Double = 0
    var windowDays: Int = 30
    var confidence: Double = 0
    var trendSlopeKgPerWeek: Double = 0
    var avgIntakeKcal: Double = 0
    /// BMR behind this estimate — the calorie-target floor. 0 on rows written
    /// before this field existed; calorieTarget falls back to 1200 then.
    var basalKcal: Double = 0
    init(date: Date, window: Int) { self.date = date; self.windowDays = window }
}
