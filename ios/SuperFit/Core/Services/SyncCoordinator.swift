import Foundation
import SwiftData

/// Pulls HealthKit data into SwiftData. Upserts are keyed by calendar day so
/// repeated syncs are idempotent. Runs on the main actor because ModelContext
/// is not Sendable; the heavy lifting happens inside the HealthKit actor.
@MainActor
final class SyncCoordinator {
    private let health: any HealthProvider
    private let context: ModelContext
    private let cal = Calendar(identifier: .gregorian)

    init(health: any HealthProvider = HealthKitManager(), context: ModelContext) {
        self.health = health
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
        try? context.save()
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

    private func upsertSleep(_ samples: [SleepSample]) {
        let existing = fetchDays(SleepData.self, dateKey: \.date)
        for s in samples where !existing.contains(cal.startOfDay(for: s.day)) {
            let row = SleepData(date: s.day)
            row.inBedMinutes = s.inBedMinutes
            row.asleepMinutes = s.asleepMinutes
            row.deepMinutes = s.deepMinutes
            row.remMinutes = s.remMinutes
            row.coreMinutes = s.coreMinutes
            context.insert(row)
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
