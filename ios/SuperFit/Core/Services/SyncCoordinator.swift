import Foundation
import SwiftData

struct SyncChanges: Sendable, Equatable {
    var bodyMass = false
    var composition = false
    var activity = false
    var sleep = false
    var vitals = false
    var garmin = false

    var weightTrendNeedsRefresh: Bool { bodyMass }
    var hasChanges: Bool {
        bodyMass || composition || activity || sleep || vitals || garmin
    }
}

/// Pulls HealthKit data into SwiftData. Upserts are keyed by calendar day so
/// repeated syncs are idempotent. Runs on the main actor because ModelContext
/// is not Sendable; the heavy lifting happens inside the HealthKit actor.
@MainActor
final class SyncCoordinator {
    private let health: any HealthProvider
    private let garmin: any RecoveryProvider
    private let context: ModelContext
    private let cal = Calendar(identifier: .gregorian)

    init(health: any HealthProvider = HealthKitManager(),
         garmin: any RecoveryProvider = GarminProvider(),
         context: ModelContext) {
        self.health = health
        self.garmin = garmin
        self.context = context
    }

    /// Sync the last `days` of everything. Safe to call on every foreground.
    @discardableResult
    func syncAll(days: Int = 90) async -> SyncChanges {
        guard health.isAvailable else { return SyncChanges() }
        let range = DateInterval(start: .now.addingTimeInterval(-Double(days) * 86_400), end: .now)
        let storedRange = DateInterval(start: cal.startOfDay(for: range.start), end: range.end)
        try? await health.requestAuthorization()

        async let mass = try? health.bodyMass(in: range)
        async let bodyFat = try? health.bodyFatPercentage(in: range)
        async let leanMass = try? health.leanBodyMass(in: range)
        async let activity = try? health.dailyActivity(in: range)
        async let sleep = try? health.sleep(in: range)
        async let rhr = try? health.restingHeartRate(in: range)
        async let hrv = try? health.hrv(in: range)

        var changes = SyncChanges()
        changes.bodyMass = upsertBodyMass(await mass ?? [], in: storedRange)
        changes.composition = upsertComposition(bodyFat: await bodyFat ?? [],
                                                leanMass: await leanMass ?? [],
                                                in: storedRange)
        changes.activity = upsertActivity(await activity ?? [], in: storedRange)
        changes.sleep = upsertSleep(await sleep ?? [], in: storedRange)
        changes.vitals = upsertVitals(rhr: await rhr ?? [], hrv: await hrv ?? [],
                                      in: storedRange)

        // Garmin last so its HRV / staged sleep overwrite HealthKit's — Garmin
        // Connect doesn't export those to Apple Health, so its values are the
        // only real readings when a Garmin watch is the wearable.
        if await garmin.isLinked,
           let metrics = try? await garmin.recoveryMetrics(in: range) {
            changes.garmin = applyGarmin(metrics, in: storedRange)
        }
        if changes.hasChanges { try? context.save() }
        return changes
    }

    private func applyGarmin(_ metrics: [RecoveryMetrics], in range: DateInterval) -> Bool {
        let start = range.start
        let end = range.end
        let vitalQuery = FetchDescriptor<DailyVitals>(
            predicate: #Predicate { $0.date >= start && $0.date <= end })
        let vitalRows = (try? context.fetch(vitalQuery)) ?? []
        var vitalsByDay = Dictionary(vitalRows.map { (cal.startOfDay(for: $0.date), $0) },
                                     uniquingKeysWith: { a, _ in a })
        let sleepQuery = FetchDescriptor<SleepData>(
            predicate: #Predicate { $0.date >= start && $0.date <= end })
        let sleepRows = (try? context.fetch(sleepQuery)) ?? []
        var sleepByDay = Dictionary(sleepRows.map { (cal.startOfDay(for: $0.date), $0) },
                                    uniquingKeysWith: { a, _ in a })
        var changed = false

        for m in metrics {
            let day = cal.startOfDay(for: m.day)
            if m.hrvSDNN != nil || m.restingHR != nil {
                let row = vitalsByDay[day] ?? {
                    let r = DailyVitals(date: day)
                    context.insert(r)
                    vitalsByDay[day] = r
                    changed = true
                    return r
                }()
                if let hrv = m.hrvSDNN, row.hrvSDNN != hrv {
                    row.hrvSDNN = hrv
                    changed = true
                }
                if let rhr = m.restingHR, row.restingHR != rhr {
                    row.restingHR = rhr
                    changed = true
                }
            }
            if let s = m.sleep {
                let row = sleepByDay[day] ?? {
                    let r = SleepData(date: day)
                    context.insert(r)
                    sleepByDay[day] = r
                    changed = true
                    return r
                }()
                if row.inBedMinutes != s.inBedMinutes { row.inBedMinutes = s.inBedMinutes; changed = true }
                if row.asleepMinutes != s.asleepMinutes { row.asleepMinutes = s.asleepMinutes; changed = true }
                if row.deepMinutes != s.deepMinutes { row.deepMinutes = s.deepMinutes; changed = true }
                if row.remMinutes != s.remMinutes { row.remMinutes = s.remMinutes; changed = true }
                if row.coreMinutes != s.coreMinutes { row.coreMinutes = s.coreMinutes; changed = true }
                if let bedtime = s.bedtime, row.bedtime != bedtime { row.bedtime = bedtime; changed = true }
                if let wakeTime = s.wakeTime, row.wakeTime != wakeTime { row.wakeTime = wakeTime; changed = true }
            }
        }
        return changed
    }

    /// One weight row per day, whatever the source hands over.
    ///
    /// `existing` is inserted into as it goes rather than being a snapshot taken
    /// before the loop. As a snapshot it only knew about days already on disk,
    /// so a day carrying several HealthKit readings — a smart scale that writes
    /// on every step-on, or a manual entry beside a synced one — inserted a row
    /// per reading. The engine averages same-day weights so the estimate
    /// survived, but the weight list showed the day two or three times.
    ///
    /// Sorted by weight so the *lowest* reading of a day is the one kept, which
    /// is the rule `DailyWeight` applies everywhere else. Storing one row per day
    /// and storing the right one are the same job here: the engines collapse by
    /// day anyway, so a heavier duplicate would only ever be noise in the list.
    private func upsertBodyMass(_ samples: [BodyMassSample], in range: DateInterval) -> Bool {
        let start = range.start
        let end = range.end
        let query = FetchDescriptor<BodyMetrics>(
            predicate: #Predicate { $0.date >= start && $0.date <= end })
        let rows = (try? context.fetch(query)) ?? []
        var changed = false
        var byDay: [Date: BodyMetrics] = [:]
        for (day, duplicates) in Dictionary(grouping: rows,
                                             by: { cal.startOfDay(for: $0.date) }) {
            guard let canonical = duplicates.min(by: { $0.weightKg < $1.weightKg }) else { continue }
            for duplicate in duplicates where duplicate !== canonical {
                canonical.bodyFatPct = canonical.bodyFatPct ?? duplicate.bodyFatPct
                canonical.leanMassKg = canonical.leanMassKg ?? duplicate.leanMassKg
                context.delete(duplicate)
                changed = true
            }
            byDay[day] = canonical
        }

        let lowestByDay = Dictionary(grouping: samples,
                                     by: { cal.startOfDay(for: $0.date) })
            .compactMapValues { $0.min(by: { $0.kg < $1.kg }) }
        for (day, sample) in lowestByDay {
            if let row = byDay[day] {
                guard sample.kg < row.weightKg else { continue }
                row.weightKg = sample.kg
                row.date = sample.date
                row.sourceRaw = MetricSource.healthKit.rawValue
            } else {
                let row = BodyMetrics(date: sample.date, weightKg: sample.kg, source: .healthKit)
                context.insert(row)
                byDay[day] = row
            }
            changed = true
        }
        return changed
    }

    /// Body fat and lean mass land on the same day's weight row. Smart scales
    /// write these to HealthKit alongside weight, and until now the app read the
    /// permission but never the data — leaving `MacroCalculator`'s lean-mass
    /// protein path and the Katch-McArdle prior permanently inert.
    ///
    /// Lean mass is taken directly when HealthKit has it, and derived from body
    /// fat otherwise. Both are stored: body fat is what the user recognises,
    /// lean mass is what the engines use.
    private func upsertComposition(bodyFat: [SampleValue], leanMass: [SampleValue],
                                   in range: DateInterval) -> Bool {
        let start = range.start
        let end = range.end
        let query = FetchDescriptor<BodyMetrics>(
            predicate: #Predicate { $0.date >= start && $0.date <= end })
        let rows = (try? context.fetch(query)) ?? []
        let byDay = Dictionary(rows.map { (cal.startOfDay(for: $0.date), $0) },
                               uniquingKeysWith: { a, _ in a })
        var changed = false

        // Several readings a day: keep the last, matching the weight behaviour.
        func lastPerDay(_ samples: [SampleValue]) -> [Date: Double] {
            var out: [Date: Double] = [:]
            for s in samples.sorted(by: { $0.date < $1.date }) {
                out[cal.startOfDay(for: s.date)] = s.value
            }
            return out
        }
        let fatByDay = lastPerDay(bodyFat)
        let leanByDay = lastPerDay(leanMass)

        for day in Set(fatByDay.keys).union(leanByDay.keys) {
            // Composition without a weight for the same day has nothing to
            // attach to, and inventing a weight row would corrupt the trend.
            guard let row = byDay[day] else { continue }
            if let fat = fatByDay[day] {
                // HealthKit reports a fraction (0.18), the app stores percent.
                let percent = fat <= 1 ? fat * 100 : fat
                if (3...70).contains(percent), row.bodyFatPct != percent {
                    row.bodyFatPct = percent
                    changed = true
                }
            }
            if let lean = leanByDay[day], lean > 0, lean < row.weightKg {
                if row.leanMassKg != lean { row.leanMassKg = lean; changed = true }
            } else if let fat = row.bodyFatPct {
                let derived = row.weightKg * (1 - fat / 100)
                if row.leanMassKg != derived { row.leanMassKg = derived; changed = true }
            }
        }
        return changed
    }

    private func upsertActivity(_ days: [DailyActivity], in range: DateInterval) -> Bool {
        let start = range.start
        let end = range.end
        let query = FetchDescriptor<DailyEnergy>(
            predicate: #Predicate { $0.date >= start && $0.date <= end })
        let rows = (try? context.fetch(query)) ?? []
        var changed = false
        var byDay: [Date: DailyEnergy] = [:]
        for (day, duplicates) in Dictionary(grouping: rows,
                                             by: { cal.startOfDay(for: $0.date) }) {
            guard let canonical = duplicates.max(by: { $0.steps < $1.steps }) else { continue }
            for duplicate in duplicates where duplicate !== canonical {
                canonical.activeEnergyKcal = max(canonical.activeEnergyKcal,
                                                 duplicate.activeEnergyKcal)
                canonical.basalEnergyKcal = max(canonical.basalEnergyKcal,
                                                duplicate.basalEnergyKcal)
                canonical.steps = max(canonical.steps, duplicate.steps)
                canonical.distanceKm = max(canonical.distanceKm, duplicate.distanceKm)
                canonical.flightsClimbed = max(canonical.flightsClimbed,
                                               duplicate.flightsClimbed)
                context.delete(duplicate)
                changed = true
            }
            if canonical.date != day { canonical.date = day; changed = true }
            byDay[day] = canonical
        }
        for d in days {
            let key = cal.startOfDay(for: d.day)
            let row = byDay[key] ?? {
                let r = DailyEnergy(date: key)
                context.insert(r)
                byDay[key] = r
                changed = true
                return r
            }()
            if row.activeEnergyKcal != d.activeEnergyKcal { row.activeEnergyKcal = d.activeEnergyKcal; changed = true }
            if row.basalEnergyKcal != d.basalEnergyKcal { row.basalEnergyKcal = d.basalEnergyKcal; changed = true }
            if row.steps != d.steps { row.steps = d.steps; changed = true }
            if row.distanceKm != d.distanceKm { row.distanceKm = d.distanceKm; changed = true }
            if row.flightsClimbed != d.flightsClimbed { row.flightsClimbed = d.flightsClimbed; changed = true }
        }
        return changed
    }

    /// Overwrites rather than skipping existing days, so rows written before
    /// bedtime/wake capture backfill their clock times on the next sync.
    private func upsertSleep(_ samples: [SleepSample], in range: DateInterval) -> Bool {
        let start = range.start
        let end = range.end
        let query = FetchDescriptor<SleepData>(
            predicate: #Predicate { $0.date >= start && $0.date <= end })
        let rows = (try? context.fetch(query)) ?? []
        var changed = false
        var byDay: [Date: SleepData] = [:]
        for (day, duplicates) in Dictionary(grouping: rows,
                                             by: { cal.startOfDay(for: $0.date) }) {
            guard let canonical = duplicates.max(by: { lhs, rhs in
                if lhs.asleepMinutes != rhs.asleepMinutes {
                    return lhs.asleepMinutes < rhs.asleepMinutes
                }
                let lhsStages = lhs.deepMinutes + lhs.remMinutes + lhs.coreMinutes
                let rhsStages = rhs.deepMinutes + rhs.remMinutes + rhs.coreMinutes
                if lhsStages != rhsStages { return lhsStages < rhsStages }
                return lhs.inBedMinutes < rhs.inBedMinutes
            }) else { continue }
            for duplicate in duplicates where duplicate !== canonical {
                context.delete(duplicate)
                changed = true
            }
            if canonical.date != day { canonical.date = day; changed = true }
            byDay[day] = canonical
        }
        for s in samples {
            let key = cal.startOfDay(for: s.day)
            let row = byDay[key] ?? {
                let r = SleepData(date: key)
                context.insert(r)
                byDay[key] = r
                changed = true
                return r
            }()
            if row.inBedMinutes != s.inBedMinutes { row.inBedMinutes = s.inBedMinutes; changed = true }
            if row.asleepMinutes != s.asleepMinutes { row.asleepMinutes = s.asleepMinutes; changed = true }
            if row.deepMinutes != s.deepMinutes { row.deepMinutes = s.deepMinutes; changed = true }
            if row.remMinutes != s.remMinutes { row.remMinutes = s.remMinutes; changed = true }
            if row.coreMinutes != s.coreMinutes { row.coreMinutes = s.coreMinutes; changed = true }
            if row.bedtime != s.bedtime { row.bedtime = s.bedtime; changed = true }
            if row.wakeTime != s.wakeTime { row.wakeTime = s.wakeTime; changed = true }
        }
        return changed
    }

    private func upsertVitals(rhr: [SampleValue], hrv: [SampleValue],
                              in range: DateInterval) -> Bool {
        let start = range.start
        let end = range.end
        let query = FetchDescriptor<DailyVitals>(
            predicate: #Predicate { $0.date >= start && $0.date <= end })
        let rows = (try? context.fetch(query)) ?? []
        var changed = false
        var byDay: [Date: DailyVitals] = [:]
        for (day, duplicates) in Dictionary(grouping: rows,
                                             by: { cal.startOfDay(for: $0.date) }) {
            guard let canonical = duplicates.max(by: { lhs, rhs in
                let left = (lhs.restingHR == nil ? 0 : 1) + (lhs.hrvSDNN == nil ? 0 : 1)
                let right = (rhs.restingHR == nil ? 0 : 1) + (rhs.hrvSDNN == nil ? 0 : 1)
                return left < right
            }) else { continue }
            for duplicate in duplicates where duplicate !== canonical {
                canonical.restingHR = canonical.restingHR ?? duplicate.restingHR
                canonical.hrvSDNN = canonical.hrvSDNN ?? duplicate.hrvSDNN
                context.delete(duplicate)
                changed = true
            }
            if canonical.date != day { canonical.date = day; changed = true }
            byDay[day] = canonical
        }
        func row(for date: Date) -> DailyVitals {
            let key = cal.startOfDay(for: date)
            if let r = byDay[key] { return r }
            let r = DailyVitals(date: key)
            context.insert(r)
            byDay[key] = r
            changed = true
            return r
        }
        for s in rhr {
            let target = row(for: s.date)
            if target.restingHR != s.value { target.restingHR = s.value; changed = true }
        }
        // Multiple HRV readings a day: keep the daily mean.
        var hrvByDay: [Date: [Double]] = [:]
        for s in hrv { hrvByDay[cal.startOfDay(for: s.date), default: []].append(s.value) }
        for (day, values) in hrvByDay {
            let mean = values.reduce(0, +) / Double(values.count)
            let target = row(for: day)
            if target.hrvSDNN != mean { target.hrvSDNN = mean; changed = true }
        }
        return changed
    }
}
