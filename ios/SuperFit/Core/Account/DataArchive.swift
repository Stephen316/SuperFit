import Foundation
import SwiftData

/// A portable copy of everything the user actually created.
///
/// CloudKit covers app updates, reinstalls and new devices on the same Apple ID.
/// It does not cover the cases where it isn't there: `AppSchema` explicitly falls
/// back to a local-only store when iCloud is unavailable, and nothing carries
/// data between two different Apple IDs. This file is the answer to both, and
/// the only thing the user can hold themselves.
///
/// **Derived records are not exported.** Metabolic estimates, recovery scores
/// and detected cyclical patterns are all recomputed by `AggregationService`
/// from the inputs below, so archiving them would only create a way for a
/// restored file to disagree with the data it came from.
struct DataArchive: Codable {
    static let currentVersion = 1

    var version = DataArchive.currentVersion
    var exportedAt = Date()

    var profile: ProfileDTO?
    var bodyMetrics: [BodyMetricDTO] = []
    var foods: [FoodDTO] = []
    var nutritionLogs: [NutritionLogDTO] = []
    var exercises: [ExerciseDTO] = []
    var sessions: [SessionDTO] = []
    var templates: [TemplateDTO] = []
    var supplements: [SupplementDTO] = []
    var supplementEntries: [SupplementEntryDTO] = []
    var sleep: [SleepDTO] = []
    var vitals: [VitalsDTO] = []
    var energy: [EnergyDTO] = []

    // MARK: - DTOs
    //
    // Deliberately separate from the @Model types: a SwiftData model is a
    // storage detail that changes with the schema, while an archive has to stay
    // readable by a future build. `version` is what lets that be checked.

    struct ProfileDTO: Codable {
        var birthDate: Date, heightCm: Double
        var sex: String, goal: String, activity: String
        var proteinPerKgOverride: Double
    }

    struct BodyMetricDTO: Codable {
        var date: Date, weightKg: Double
        var bodyFatPct: Double?, leanMassKg: Double?, source: String
    }

    struct FoodDTO: Codable {
        var id: UUID, source: String, remoteID: String?
        var name: String, brand: String?
        var kcal: Double, protein: Double, carbs: Double, fat: Double, fibre: Double
        var micros: [String: Double]?
        var portions: [FoodPortion]?
        var isFavorite: Bool
    }

    struct NutritionLogDTO: Codable {
        var date: Date, loggedAt: Date, foodID: UUID?, foodName: String?
        var servingGrams: Double
        var kcal: Double, protein: Double, carbs: Double, fat: Double, fibre: Double
        var micros: [String]
        var meal: String
    }

    struct ExerciseDTO: Codable {
        var id: UUID, name: String, category: String
        var tension: [String], bodyweightFraction: Double, isCustom: Bool
    }

    struct SessionDTO: Codable {
        var id: UUID, startedAt: Date, endedAt: Date?, templateName: String?
        var sets: [SetDTO]

        struct SetDTO: Codable {
            var order: Int, exerciseID: UUID?
            var weightKg: Double, reps: Int, rir: Int?
            var isWarmup: Bool, completedAt: Date?
        }
    }

    struct TemplateDTO: Codable {
        var id: UUID, name: String, createdAt: Date, exerciseIDs: [UUID]
    }

    struct SupplementDTO: Codable {
        var id: UUID, name: String, category: String
        var servingLabel: String, servingGrams: Double?
        var kcal: Double, protein: Double, carbs: Double, fat: Double, fibre: Double
        var micros: [String], isCustom: Bool
    }

    struct SupplementEntryDTO: Codable {
        var id: UUID, supplementID: UUID?, kind: String, servings: Double
        var date: Date?, startedOn: Date?, stoppedOn: Date?
    }

    struct SleepDTO: Codable {
        var date: Date, inBed: Int, asleep: Int, deep: Int, rem: Int, core: Int
        var bedtime: Date?, wakeTime: Date?
    }

    struct VitalsDTO: Codable {
        var date: Date, restingHR: Double?, hrvSDNN: Double?
    }

    struct EnergyDTO: Codable {
        var date: Date, active: Double, basal: Double
        var steps: Int, distanceKm: Double, flights: Int
    }
}

@MainActor
enum DataArchiveService {

    enum ImportMode {
        /// Add what isn't already there, keyed by natural identity. The safe
        /// default: restoring a stale backup can't destroy newer data.
        case merge
        /// Erase everything first. For moving to a different Apple ID, where
        /// merging two histories would produce a nonsense timeline.
        case replace
    }

    struct ImportResult {
        var added = 0
        var skipped = 0
    }

    // MARK: - Export

    static func export(context: ModelContext) -> DataArchive {
        var archive = DataArchive()

        if let p = (try? context.fetch(FetchDescriptor<UserProfile>()))?.first {
            archive.profile = .init(birthDate: p.birthDate, heightCm: p.heightCm,
                                    sex: p.sexRaw, goal: p.goalRaw, activity: p.activityRaw,
                                    proteinPerKgOverride: p.proteinPerKgOverride)
        }
        archive.bodyMetrics = fetch(context).map { (m: BodyMetrics) in
            .init(date: m.date, weightKg: m.weightKg, bodyFatPct: m.bodyFatPct,
                  leanMassKg: m.leanMassKg, source: m.sourceRaw)
        }
        archive.foods = fetch(context).map { (f: Food) in
            .init(id: f.id, source: f.sourceRaw, remoteID: f.remoteID, name: f.name,
                  brand: f.brand, kcal: f.kcalPer100g, protein: f.proteinPer100g,
                  carbs: f.carbsPer100g, fat: f.fatPer100g, fibre: f.fibrePer100g,
                  micros: f.microsJSON.flatMap {
                      try? JSONDecoder().decode([String: Double].self, from: $0) },
                  portions: f.portionsJSON.flatMap {
                      try? JSONDecoder().decode([FoodPortion].self, from: $0) },
                  isFavorite: f.isFavorite)
        }
        archive.nutritionLogs = fetch(context).map { (l: NutritionLog) in
            .init(date: l.date, loggedAt: l.loggedAt, foodID: l.foodID, foodName: l.foodName,
                  servingGrams: l.servingGrams, kcal: l.kcal, protein: l.proteinG,
                  carbs: l.carbsG, fat: l.fatG, fibre: l.fibreG,
                  micros: l.microsRaw, meal: l.mealRaw)
        }
        archive.exercises = fetch(context).map { (e: Exercise) in
            .init(id: e.id, name: e.name, category: e.categoryRaw, tension: e.tensionRaw,
                  bodyweightFraction: e.bodyweightFraction, isCustom: e.isCustom)
        }
        archive.sessions = fetch(context).map { (s: TrainingSession) in
            .init(id: s.id, startedAt: s.startedAt, endedAt: s.endedAt,
                  templateName: s.templateName,
                  sets: (s.sets ?? []).sorted { $0.order < $1.order }.map {
                      .init(order: $0.order, exerciseID: $0.exerciseID, weightKg: $0.weightKg,
                            reps: $0.reps, rir: $0.rir, isWarmup: $0.isWarmup,
                            completedAt: $0.completedAt)
                  })
        }
        archive.templates = fetch(context).map { (t: WorkoutTemplate) in
            .init(id: t.id, name: t.name, createdAt: t.createdAt,
                  exerciseIDs: t.orderedExerciseIDs)
        }
        archive.supplements = fetch(context).map { (s: Supplement) in
            .init(id: s.id, name: s.name, category: s.categoryRaw,
                  servingLabel: s.servingLabel, servingGrams: s.servingGrams,
                  kcal: s.kcal, protein: s.proteinG, carbs: s.carbsG, fat: s.fatG,
                  fibre: s.fibreG, micros: s.microsRaw, isCustom: s.isCustom)
        }
        archive.supplementEntries = fetch(context).map { (e: SupplementEntry) in
            .init(id: e.id, supplementID: e.supplementID, kind: e.kindRaw,
                  servings: e.servings, date: e.date,
                  startedOn: e.startedOn, stoppedOn: e.stoppedOn)
        }
        archive.sleep = fetch(context).map { (s: SleepData) in
            .init(date: s.date, inBed: s.inBedMinutes, asleep: s.asleepMinutes,
                  deep: s.deepMinutes, rem: s.remMinutes, core: s.coreMinutes,
                  bedtime: s.bedtime, wakeTime: s.wakeTime)
        }
        archive.vitals = fetch(context).map { (v: DailyVitals) in
            .init(date: v.date, restingHR: v.restingHR, hrvSDNN: v.hrvSDNN)
        }
        archive.energy = fetch(context).map { (e: DailyEnergy) in
            .init(date: e.date, active: e.activeEnergyKcal, basal: e.basalEnergyKcal,
                  steps: e.steps, distanceKm: e.distanceKm, flights: e.flightsClimbed)
        }
        return archive
    }

    static func encode(_ archive: DataArchive) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(archive)
    }

    static func decode(_ data: Data) throws -> DataArchive {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let archive = try decoder.decode(DataArchive.self, from: data)
        guard archive.version <= DataArchive.currentVersion else {
            throw ArchiveError.newerVersion(archive.version)
        }
        return archive
    }

    enum ArchiveError: LocalizedError {
        case newerVersion(Int)
        var errorDescription: String? {
            switch self {
            case .newerVersion(let v):
                return "This backup was made by a newer version of SuperFit (format \(v)). Update the app and try again."
            }
        }
    }

    // MARK: - Import

    @discardableResult
    static func restore(_ archive: DataArchive, mode: ImportMode,
                        context: ModelContext) -> ImportResult {
        var result = ImportResult()
        let cal = Calendar.current

        if mode == .replace { eraseAll(context: context) }

        if let p = archive.profile {
            let profile = (try? context.fetch(FetchDescriptor<UserProfile>()))?.first
                ?? { let n = UserProfile(); context.insert(n); return n }()
            profile.birthDate = p.birthDate
            profile.heightCm = p.heightCm
            profile.sexRaw = p.sex
            profile.goalRaw = p.goal
            profile.activityRaw = p.activity
            profile.proteinPerKgOverride = p.proteinPerKgOverride
        }

        // Day-keyed rows dedupe by day; everything else by identity. Merging a
        // backup must never double a day's weight or a training session.
        let existingWeightDays = Set(fetch(context).map { (m: BodyMetrics) in cal.startOfDay(for: m.date) })
        for m in archive.bodyMetrics {
            guard !existingWeightDays.contains(cal.startOfDay(for: m.date)) else { result.skipped += 1; continue }
            let row = BodyMetrics(date: m.date, weightKg: m.weightKg,
                                  source: MetricSource(rawValue: m.source) ?? .manual)
            row.bodyFatPct = m.bodyFatPct
            row.leanMassKg = m.leanMassKg
            context.insert(row)
            result.added += 1
        }

        let existingFoodIDs = Set(fetch(context).map { (f: Food) in f.id })
        for f in archive.foods where !existingFoodIDs.contains(f.id) {
            let row = Food(name: f.name, source: FoodSource(rawValue: f.source) ?? .custom)
            row.id = f.id
            row.remoteID = f.remoteID
            row.brand = f.brand
            row.kcalPer100g = f.kcal
            row.proteinPer100g = f.protein
            row.carbsPer100g = f.carbs
            row.fatPer100g = f.fat
            row.fibrePer100g = f.fibre
            row.microsJSON = f.micros.flatMap { try? JSONEncoder().encode($0) }
            row.portionsJSON = f.portions.flatMap { try? JSONEncoder().encode($0) }
            row.isFavorite = f.isFavorite
            context.insert(row)
            result.added += 1
        }

        // A log has no natural key, so identity is the tuple that makes two
        // entries genuinely the same: same food, same moment, same portion.
        let existingLogKeys = Set(fetch(context).map { (l: NutritionLog) in
            "\(l.loggedAt.timeIntervalSince1970)|\(l.foodName ?? "")|\(l.servingGrams)"
        })
        for l in archive.nutritionLogs {
            let key = "\(l.loggedAt.timeIntervalSince1970)|\(l.foodName ?? "")|\(l.servingGrams)"
            guard !existingLogKeys.contains(key) else { result.skipped += 1; continue }
            let row = NutritionLog(date: l.date, meal: MealSlot(rawValue: l.meal) ?? .snack)
            row.loggedAt = l.loggedAt
            row.foodID = l.foodID
            row.foodName = l.foodName
            row.servingGrams = l.servingGrams
            row.kcal = l.kcal
            row.proteinG = l.protein
            row.carbsG = l.carbs
            row.fatG = l.fat
            row.fibreG = l.fibre
            row.microsRaw = l.micros
            context.insert(row)
            result.added += 1
        }

        let existingExerciseIDs = Set(fetch(context).map { (e: Exercise) in e.id })
        let existingExerciseNames = Set(fetch(context).map { (e: Exercise) in e.name })
        for e in archive.exercises {
            // Built-ins are re-seeded on launch with fresh ids, so skip by name
            // too or every restore would duplicate the whole catalog.
            guard !existingExerciseIDs.contains(e.id),
                  !existingExerciseNames.contains(e.name) else { result.skipped += 1; continue }
            let row = Exercise(name: e.name,
                               category: ExerciseCategory(rawValue: e.category) ?? .barbell,
                               tension: [:], bodyweightFraction: e.bodyweightFraction,
                               isCustom: e.isCustom)
            row.id = e.id
            row.tensionRaw = e.tension
            context.insert(row)
            result.added += 1
        }

        let existingSessionIDs = Set(fetch(context).map { (s: TrainingSession) in s.id })
        for s in archive.sessions where !existingSessionIDs.contains(s.id) {
            let session = TrainingSession(templateName: s.templateName)
            session.id = s.id
            session.startedAt = s.startedAt
            session.endedAt = s.endedAt
            context.insert(session)
            for set in s.sets {
                guard let exerciseID = set.exerciseID else { continue }
                let entry = SetEntry(order: set.order, exerciseID: exerciseID,
                                     weightKg: set.weightKg, reps: set.reps)
                entry.rir = set.rir
                entry.isWarmup = set.isWarmup
                entry.completedAt = set.completedAt
                entry.session = session
                context.insert(entry)
            }
            result.added += 1
        }

        let existingTemplateNames = Set(fetch(context).map { (t: WorkoutTemplate) in t.name })
        for t in archive.templates where !existingTemplateNames.contains(t.name) {
            let template = WorkoutTemplate(name: t.name)
            template.id = t.id
            template.createdAt = t.createdAt
            context.insert(template)
            for (i, id) in t.exerciseIDs.enumerated() {
                let item = WorkoutTemplateItem(order: i, exerciseID: id)
                item.template = template
                context.insert(item)
            }
            result.added += 1
        }

        let existingSupplementNames = Set(fetch(context).map { (s: Supplement) in s.name })
        for s in archive.supplements where !existingSupplementNames.contains(s.name) {
            let row = Supplement(name: s.name,
                                 category: SupplementCategory(rawValue: s.category) ?? .health,
                                 servingLabel: s.servingLabel,
                                 servingGrams: s.servingGrams,
                                 isCustom: s.isCustom)
            row.id = s.id
            row.kcal = s.kcal
            row.proteinG = s.protein
            row.carbsG = s.carbs
            row.fatG = s.fat
            row.fibreG = s.fibre
            row.microsRaw = s.micros
            context.insert(row)
            result.added += 1
        }

        let existingEntryIDs = Set(fetch(context).map { (e: SupplementEntry) in e.id })
        for e in archive.supplementEntries where !existingEntryIDs.contains(e.id) {
            guard let supplementID = e.supplementID else { continue }
            let row = SupplementEntry(supplementID: supplementID,
                                      kind: SupplementEntryKind(rawValue: e.kind) ?? .once,
                                      servings: e.servings)
            row.id = e.id
            row.date = e.date
            row.startedOn = e.startedOn
            row.stoppedOn = e.stoppedOn
            context.insert(row)
            result.added += 1
        }

        let existingSleepDays = Set(fetch(context).map { (s: SleepData) in cal.startOfDay(for: s.date) })
        for s in archive.sleep where !existingSleepDays.contains(cal.startOfDay(for: s.date)) {
            let row = SleepData(date: s.date)
            row.inBedMinutes = s.inBed
            row.asleepMinutes = s.asleep
            row.deepMinutes = s.deep
            row.remMinutes = s.rem
            row.coreMinutes = s.core
            row.bedtime = s.bedtime
            row.wakeTime = s.wakeTime
            context.insert(row)
            result.added += 1
        }

        let existingVitalDays = Set(fetch(context).map { (v: DailyVitals) in cal.startOfDay(for: v.date) })
        for v in archive.vitals where !existingVitalDays.contains(cal.startOfDay(for: v.date)) {
            let row = DailyVitals(date: v.date)
            row.restingHR = v.restingHR
            row.hrvSDNN = v.hrvSDNN
            context.insert(row)
            result.added += 1
        }

        let existingEnergyDays = Set(fetch(context).map { (e: DailyEnergy) in cal.startOfDay(for: e.date) })
        for e in archive.energy where !existingEnergyDays.contains(cal.startOfDay(for: e.date)) {
            let row = DailyEnergy(date: e.date)
            row.activeEnergyKcal = e.active
            row.basalEnergyKcal = e.basal
            row.steps = e.steps
            row.distanceKm = e.distanceKm
            row.flightsClimbed = e.flights
            context.insert(row)
            result.added += 1
        }

        try? context.save()
        // Estimates and recovery scores are derived, so they're rebuilt from the
        // restored inputs rather than carried in the file.
        AggregationService(context: context).runAll()
        return result
    }

    /// Wipes every user record. Only reachable from an explicitly confirmed
    /// action — never as a side effect of signing out.
    static func eraseAll(context: ModelContext) {
        for model in AppSchema.models {
            try? context.delete(model: model)
        }
        try? context.save()
    }

    private static func fetch<T: PersistentModel>(_ context: ModelContext) -> [T] {
        (try? context.fetch(FetchDescriptor<T>())) ?? []
    }
}
