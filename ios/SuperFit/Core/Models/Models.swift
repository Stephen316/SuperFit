import Foundation
import SwiftData

// CloudKit constraints: every relationship optional, every scalar defaulted,
// no unique constraints (dedupe on natural keys in code).

enum MetricSource: String, Codable, Sendable { case manual, healthKit }
enum MealSlot: String, Codable, CaseIterable, Sendable { case breakfast, lunch, dinner, snack }
enum FoodSource: String, Codable, Sendable { case openFoodFacts, usda, custom, supplement }
/// The muscles volume is tracked against — 37 of them, down to the head.
///
/// Split this finely because the coarse version can't answer the questions the
/// tracking exists for. "Shoulders" hides the single most common imbalance in a
/// training week — pressing hammers the front delts while the rear delts get
/// nothing — and one "back" figure can read as well-trained on pulldowns alone
/// while the rhomboids and mid-traps go untouched.
///
/// The rule for splitting is whether an exercise can bias one head over its
/// neighbour. Overhead work favours the triceps long head; a bent knee shifts
/// calf work from gastrocnemius to soleus; hip extension loads adductor magnus
/// where adduction loads longus. Each of those is a programming decision someone
/// can act on, so each earns a case.
///
/// **The two gastrocnemius heads are the deliberate exception.** Nothing biases
/// the medial against the lateral — foot rotation is often claimed to, and the
/// effect does not survive measurement — so splitting them would add a row
/// nobody could ever act on. They share `.gastrocnemius`.
///
/// The cost of every case is a judgement call on all 130 catalogued lifts, which
/// is the reason the rule is "can it change what you do" rather than "is it
/// anatomically distinct".
enum MuscleGroup: String, Codable, CaseIterable, Sendable {
    case upperChest, chest, serratus
    case frontDelts, sideDelts, rearDelts
    case upperTraps, middleTraps, lowerTraps, rhomboids, lats, erectorSpinae
    case biceps, tricepsLong, tricepsLateral, tricepsMedial
    case brachioradialis, wristFlexors, wristExtensors
    case upperAbs, lowerAbs, obliques
    case rectusFemoris, vastusLateralis, vastusMedialis
    case bicepsFemoris, semitendinosus
    case gluteusMaximus, gluteusMedius
    case adductorLongus, adductorMagnus, pectineus, sartorius
    case gastrocnemius, soleus, tibialisAnterior, peroneals

    var displayName: String {
        switch self {
        case .upperChest:      return "Upper chest"
        // Both heads of pec major. Named by position because that is how the
        // bench angle addresses them; the serratus is next door, not chest.
        case .chest:           return "Lower chest"
        case .serratus:        return "Serratus"
        case .frontDelts:      return "Front delts"
        case .sideDelts:       return "Side delts"
        case .rearDelts:       return "Rear delts"
        case .upperTraps:      return "Upper traps"
        case .middleTraps:     return "Mid traps"
        case .lowerTraps:      return "Lower traps"
        case .rhomboids:       return "Rhomboids"
        case .lats:            return "Lats"
        case .erectorSpinae:   return "Lower back"
        case .biceps:          return "Biceps"
        case .tricepsLong:     return "Triceps long head"
        case .tricepsLateral:  return "Triceps lateral head"
        case .tricepsMedial:   return "Triceps medial head"
        case .brachioradialis: return "Brachioradialis"
        case .wristFlexors:    return "Wrist flexors"
        case .wristExtensors:  return "Wrist extensors"
        case .upperAbs:        return "Upper abs"
        case .lowerAbs:        return "Lower abs"
        case .obliques:        return "Obliques"
        case .rectusFemoris:   return "Rectus femoris"
        case .vastusLateralis: return "Vastus lateralis"
        case .vastusMedialis:  return "Vastus medialis"
        case .bicepsFemoris:   return "Biceps femoris"
        case .semitendinosus:  return "Medial hamstrings"
        case .gluteusMaximus:  return "Glute max"
        case .gluteusMedius:   return "Glute med"
        case .adductorLongus:  return "Adductors"
        case .adductorMagnus:  return "Adductor magnus"
        case .pectineus:       return "Pectineus"
        case .sartorius:       return "Sartorius"
        case .gastrocnemius:   return "Gastrocnemius"
        case .soleus:          return "Soleus"
        case .tibialisAnterior: return "Tibialis anterior"
        case .peroneals:       return "Peroneals"
        }
    }

    /// Raw values written before the heads were split, mapped to the reading the
    /// old label most often meant.
    ///
    /// Only reachable through custom exercises and stored logs — built-ins are
    /// re-synced from the catalogue on launch. A coarse label becomes the head
    /// that dominates it rather than being dropped: "quads" was nearly always
    /// squat or press work, which is vastus-led, and "triceps" without further
    /// detail is most often pressing, where the lateral head leads.
    static let legacyNames: [String: MuscleGroup] = [
        "shoulders": .sideDelts,
        "back": .lats,
        "core": .upperAbs,
        "abs": .upperAbs,
        "forearms": .wristFlexors,
        "traps": .upperTraps,
        "upperBack": .rhomboids,
        "lowerBack": .erectorSpinae,
        "quads": .vastusLateralis,
        "hamstrings": .bicepsFemoris,
        "glutes": .gluteusMaximus,
        "calves": .gastrocnemius,
        "adductors": .adductorLongus,
        "abductors": .gluteusMedius,
        "triceps": .tricepsLateral,
    ]

    /// Decodes a stored raw value, falling back to the pre-split names.
    init?(stored raw: String) {
        if let m = MuscleGroup(rawValue: raw) { self = m; return }
        guard let m = MuscleGroup.legacyNames[raw] else { return nil }
        self = m
    }
}
enum ExerciseCategory: String, Codable, Sendable { case barbell, dumbbell, machine, cable, bodyweight }

@Model
final class UserProfile {
    var id: UUID = UUID()
    /// 1 January 2000, until the user says otherwise.
    ///
    /// The epoch was the old default, which made every untouched profile 56
    /// years old. That is not a neutral placeholder: age is a term in
    /// Mifflin-St Jeor (−5 kcal per year) and in the Tanaka max-heart-rate
    /// estimate, so it was quietly costing a new user ~130 kcal on their basal
    /// estimate and shifting their cardio load bands, before they had entered
    /// anything at all.
    ///
    /// Anchored at **noon UTC**, not midnight. Stored as an instant but shown as
    /// a date, so a midnight anchor reads as 31 December 1999 anywhere west of
    /// Greenwich — the default would look wrong in the picker for every user in
    /// the Americas. Noon holds the date from UTC−12 to UTC+11.
    var birthDate: Date = Date(timeIntervalSince1970: 946_728_000)
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
    /// nil means unknown; zero is a measured food with no water.
    var waterGPer100g: Double?
    /// Optional liquid density used to convert ml/fl oz into the gram basis
    /// nutrition values use. Volume-labelled portions can also provide this.
    var gramsPerMillilitre: Double?
    var microsJSON: Data?                  // [String: Double] per 100 g
    /// USDA household measures, JSON [FoodPortion]. Cached so a food logged
    /// once keeps its "1 medium" option offline and without a second request.
    var portionsJSON: Data?
    /// Declared allergens and "may contain", comma separated and unprefixed.
    /// Defaulted rather than optional so CloudKit accepts them; an empty string
    /// means the source published nothing, not that the food is free of them.
    var allergenTagsRaw: String = ""
    var traceTagsRaw: String = ""
    var ingredientsText: String?
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
    /// Water contributed by this exact logged portion. Snapshotted like the
    /// macros so later edits to the source food cannot rewrite hydration history.
    var waterMl: Double = 0
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
    /// Other names this lift answers to — "RDL", "military press", "bent over
    /// row". Matched when searching, **never shown**: one lift under one name
    /// keeps the list scannable and a year of logs comparable.
    var aliases: [String] = []

    init(name: String, category: ExerciseCategory, tension: [MuscleGroup: Int],
         bodyweightFraction: Double = 0, isCustom: Bool = false,
         aliases: [String] = []) {
        self.name = name
        self.categoryRaw = category.rawValue
        self.isCustom = isCustom
        self.bodyweightFraction = bodyweightFraction
        self.aliases = aliases
        self.tension = tension
    }

    /// Whether this lift answers to `term`, by its own name or any alias.
    func matches(_ term: String) -> Bool {
        let q = term.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return true }
        if name.localizedCaseInsensitiveContains(q) { return true }
        return aliases.contains { $0.localizedCaseInsensitiveContains(q) }
    }

    var tension: [MuscleGroup: Int] {
        get {
            var out: [MuscleGroup: Int] = [:]
            for entry in tensionRaw {
                let parts = entry.split(separator: ":")
                guard parts.count == 2, let m = MuscleGroup(stored: String(parts[0])),
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

    /// The muscle this lift is for, or nil when it has no tension map.
    ///
    /// Optional rather than defaulting. It used to fall back to `.upperAbs`,
    /// which is not a safe default but a wrong answer: a lift with no scores
    /// would report itself as an ab exercise, and nothing downstream could tell
    /// that apart from one that genuinely is. Nothing calls this today, so the
    /// wrongness was latent — which is exactly when it is cheapest to fix.
    var primaryMuscle: MuscleGroup? {
        tension.max { $0.value < $1.value }?.key
    }
}

/// User-saved reusable workout (built-ins live in ExerciseLibrary.templates).
@Model
final class WorkoutTemplate {
    static let maximumSaved = 8

    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date()
    @Relationship(deleteRule: .cascade) var items: [WorkoutTemplateItem]? = []

    init(name: String) { self.name = name }

    static func canCreate(savedCount: Int) -> Bool {
        savedCount < maximumSaved
    }

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
    /// Minute-level heart rate as compact JSON. Imported workouts without a
    /// time series continue to use their session average.
    var heartRateSegmentsJSON: Data?
    /// 0 means the user has not rated the session; valid ratings are 1...10.
    var perceivedExertion: Int = 0
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

    var heartRateSegments: [HeartRateSegment] {
        get {
            heartRateSegmentsJSON.flatMap {
                try? JSONDecoder().decode([HeartRateSegment].self, from: $0)
            } ?? []
        }
        set {
            heartRateSegmentsJSON = newValue.isEmpty ? nil : try? JSONEncoder().encode(newValue)
        }
    }

    var sessionRPE: Int? {
        get { (1...10).contains(perceivedExertion) ? perceivedExertion : nil }
        set { perceivedExertion = min(max(newValue ?? 0, 0), 10) }
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
    /// 0 means unrated; valid session-RPE ratings are 1...10.
    var perceivedExertion: Int = 0
    @Relationship(deleteRule: .cascade) var sets: [SetEntry]? = []

    init(startedAt: Date = .now, templateName: String? = nil) {
        self.startedAt = startedAt
        self.templateName = templateName
    }


    var sessionRPE: Int? {
        get { (1...10).contains(perceivedExertion) ? perceivedExertion : nil }
        set { perceivedExertion = min(max(newValue ?? 0, 0), 10) }
    }
}

@Model
final class SetEntry {
    var order: Int = 0
    var exerciseID: UUID?
    /// nil until the user enters a number. 0 is a value they typed, never the
    /// default — the row shows "—" while this is nil, so an untouched set can't
    /// masquerade as a real 0 kg lift.
    var weightKg: Double?
    var reps: Int = 0
    var rir: Int?
    var restSeconds: Int?
    var completedAt: Date?
    var isWarmup: Bool = false
    var session: TrainingSession?

    init(order: Int, exerciseID: UUID, weightKg: Double? = nil, reps: Int) {
        self.order = order
        self.exerciseID = exerciseID
        self.weightKg = weightKg
        self.reps = reps
    }

    /// Zero when the weight hasn't been entered — an unlogged set contributes no
    /// tonnage rather than being undefined.
    var volumeKg: Double { isWarmup ? 0 : (weightKg ?? 0) * Double(reps) }
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

/// Daily cardiovascular strain, the exertion sibling of the recovery score.
/// Derived from workouts by `StrainEngine` and rebuilt on each aggregation pass,
/// so like `RecoveryScoreRecord` it is not archived — a restore recomputes it.
@Model
final class StrainRecord {
    var date: Date = Date()
    var strain: Double = 0            // 0…100
    var rawTrimp: Double = 0
    var bandRaw: String = ""
    /// Fraction of the day's workouts that carried heart rate. 0 means no
    /// heart-rate-carrying workout, so the strain is "no data", not a real zero.
    var dataCompleteness: Double = 0

    init(date: Date, strain: Double, rawTrimp: Double, bandRaw: String, dataCompleteness: Double) {
        self.date = date; self.strain = strain; self.rawTrimp = rawTrimp
        self.bandRaw = bandRaw; self.dataCompleteness = dataCompleteness
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
