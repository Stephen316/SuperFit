import Foundation
import SwiftData

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
    func syncAll(days: Int = 90) async {
        guard health.isAvailable else { return }
        let range = DateInterval(start: .now.addingTimeInterval(-Double(days) * 86_400), end: .now)
        try? await health.requestAuthorization()

        async let mass = try? health.bodyMass(in: range)
        async let activity = try? health.dailyActivity(in: range)
        async let sleep = try? health.sleep(in: range)
        async let rhr = try? health.restingHeartRate(in: range)
        async let hrv = try? health.hrv(in: range)

        upsertBodyMass(await mass ?? [])
        upsertActivity(await activity ?? [])
        upsertSleep(await sleep ?? [])
        upsertVitals(rhr: await rhr ?? [], hrv: await hrv ?? [])

        // Garmin last so its HRV / staged sleep overwrite HealthKit's — Garmin
        // Connect doesn't export those to Apple Health, so its values are the
        // only real readings when a Garmin watch is the wearable.
        if await garmin.isLinked,
           let metrics = try? await garmin.recoveryMetrics(in: range) {
            applyGarmin(metrics)
        }
        try? context.save()
    }

    private func applyGarmin(_ metrics: [RecoveryMetrics]) {
        let vitalRows = (try? context.fetch(FetchDescriptor<DailyVitals>())) ?? []
        var vitalsByDay = Dictionary(vitalRows.map { (cal.startOfDay(for: $0.date), $0) },
                                     uniquingKeysWith: { a, _ in a })
        let sleepRows = (try? context.fetch(FetchDescriptor<SleepData>())) ?? []
        var sleepByDay = Dictionary(sleepRows.map { (cal.startOfDay(for: $0.date), $0) },
                                    uniquingKeysWith: { a, _ in a })

        for m in metrics {
            let day = cal.startOfDay(for: m.day)
            if m.hrvSDNN != nil || m.restingHR != nil {
                let row = vitalsByDay[day] ?? {
                    let r = DailyVitals(date: day)
                    context.insert(r)
                    vitalsByDay[day] = r
                    return r
                }()
                if let hrv = m.hrvSDNN { row.hrvSDNN = hrv }
                if let rhr = m.restingHR { row.restingHR = rhr }
            }
            if let s = m.sleep {
                let row = sleepByDay[day] ?? {
                    let r = SleepData(date: day)
                    context.insert(r)
                    sleepByDay[day] = r
                    return r
                }()
                row.inBedMinutes = s.inBedMinutes
                row.asleepMinutes = s.asleepMinutes
                row.deepMinutes = s.deepMinutes
                row.remMinutes = s.remMinutes
                row.coreMinutes = s.coreMinutes
                if let bedtime = s.bedtime { row.bedtime = bedtime }
                if let wakeTime = s.wakeTime { row.wakeTime = wakeTime }
            }
        }
    }

    private func upsertBodyMass(_ samples: [BodyMassSample]) {
        let existing = fetchDays(BodyMetrics.self, dateKey: \.date)
        for s in samples where !existing.contains(cal.startOfDay(for: s.date)) {
            context.insert(BodyMetrics(date: s.date, weightKg: s.kg, source: .healthKit))
        }
    }

    private func upsertActivity(_ days: [DailyActivity]) {
        let rows = (try? context.fetch(FetchDescriptor<DailyEnergy>())) ?? []
        var byDay = Dictionary(uniqueKeysWithValues: rows.map { (cal.startOfDay(for: $0.date), $0) })
        for d in days {
            let key = cal.startOfDay(for: d.day)
            let row = byDay[key] ?? {
                let r = DailyEnergy(date: key)
                context.insert(r)
                byDay[key] = r
                return r
            }()
            row.activeEnergyKcal = d.activeEnergyKcal
            row.basalEnergyKcal = d.basalEnergyKcal
            row.steps = d.steps
            row.distanceKm = d.distanceKm
            row.flightsClimbed = d.flightsClimbed
        }
    }

    /// Overwrites rather than skipping existing days, so rows written before
    /// bedtime/wake capture backfill their clock times on the next sync.
    private func upsertSleep(_ samples: [SleepSample]) {
        let rows = (try? context.fetch(FetchDescriptor<SleepData>())) ?? []
        var byDay = Dictionary(rows.map { (cal.startOfDay(for: $0.date), $0) },
                               uniquingKeysWith: { a, _ in a })
        for s in samples {
            let key = cal.startOfDay(for: s.day)
            let row = byDay[key] ?? {
                let r = SleepData(date: key)
                context.insert(r)
                byDay[key] = r
                return r
            }()
            row.inBedMinutes = s.inBedMinutes
            row.asleepMinutes = s.asleepMinutes
            row.deepMinutes = s.deepMinutes
            row.remMinutes = s.remMinutes
            row.coreMinutes = s.coreMinutes
            row.bedtime = s.bedtime
            row.wakeTime = s.wakeTime
        }
    }

    private func upsertVitals(rhr: [SampleValue], hrv: [SampleValue]) {
        let rows = (try? context.fetch(FetchDescriptor<DailyVitals>())) ?? []
        var byDay = Dictionary(uniqueKeysWithValues: rows.map { (cal.startOfDay(for: $0.date), $0) })
        func row(for date: Date) -> DailyVitals {
            let key = cal.startOfDay(for: date)
            if let r = byDay[key] { return r }
            let r = DailyVitals(date: key)
            context.insert(r)
            byDay[key] = r
            return r
        }
        for s in rhr { row(for: s.date).restingHR = s.value }
        // Multiple HRV readings a day: keep the daily mean.
        var hrvByDay: [Date: [Double]] = [:]
        for s in hrv { hrvByDay[cal.startOfDay(for: s.date), default: []].append(s.value) }
        for (day, values) in hrvByDay {
            row(for: day).hrvSDNN = values.reduce(0, +) / Double(values.count)
        }
    }

    private func fetchDays<T: PersistentModel>(_ type: T.Type, dateKey: KeyPath<T, Date>) -> Set<Date> {
        let rows = (try? context.fetch(FetchDescriptor<T>())) ?? []
        return Set(rows.map { cal.startOfDay(for: $0[keyPath: dateKey]) })
    }
}
