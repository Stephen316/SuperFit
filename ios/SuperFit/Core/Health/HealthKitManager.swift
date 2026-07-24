import Foundation
#if canImport(HealthKit)
import HealthKit
#endif

enum HealthError: Error { case unavailable, unsupportedType }

#if canImport(HealthKit)

/// Serializes all HKHealthStore access. Read-only in Phase 1 (least privilege).
actor HealthKitManager: HealthProvider {

    private let store = HKHealthStore()

    nonisolated var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private var readTypes: Set<HKObjectType> {
        var t: Set<HKObjectType> = []
        func q(_ id: HKQuantityTypeIdentifier) { if let x = HKQuantityType.quantityType(forIdentifier: id) { t.insert(x) } }
        q(.activeEnergyBurned); q(.basalEnergyBurned); q(.stepCount)
        q(.distanceWalkingRunning); q(.flightsClimbed)
        q(.bodyMass); q(.bodyFatPercentage); q(.leanBodyMass)
        q(.restingHeartRate); q(.heartRateVariabilitySDNN); q(.vo2Max); q(.heartRate)
        if let sleep = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) { t.insert(sleep) }
        t.insert(HKObjectType.workoutType())
        return t
    }

    func requestAuthorization() async throws {
        guard isAvailable else { throw HealthError.unavailable }
        try await store.requestAuthorization(toShare: [], read: readTypes)
    }

    // MARK: Body

    func bodyMass(in range: DateInterval) async throws -> [BodyMassSample] {
        try await quantitySamples(.bodyMass, unit: .gramUnit(with: .kilo), in: range)
            .map { BodyMassSample(date: $0.date, kg: $0.value) }
    }

    func bodyFatPercentage(in range: DateInterval) async throws -> [SampleValue] {
        try await quantitySamples(.bodyFatPercentage, unit: .percent(), in: range)
    }

    func leanBodyMass(in range: DateInterval) async throws -> [SampleValue] {
        try await quantitySamples(.leanBodyMass, unit: .gramUnit(with: .kilo), in: range)
    }

    // MARK: Activity (daily buckets)

    func dailyActivity(in range: DateInterval) async throws -> [DailyActivity] {
        async let active = dailySum(.activeEnergyBurned, unit: .kilocalorie(), in: range)
        async let basal = dailySum(.basalEnergyBurned, unit: .kilocalorie(), in: range)
        async let steps = dailySum(.stepCount, unit: .count(), in: range)
        async let dist = dailySum(.distanceWalkingRunning, unit: .meterUnit(with: .kilo), in: range)
        async let flights = dailySum(.flightsClimbed, unit: .count(), in: range)

        let (a, b, s, d, f) = try await (active, basal, steps, dist, flights)
        let days = Set(a.keys).union(b.keys).union(s.keys).union(d.keys).union(f.keys)
        return days.sorted().map { day in
            DailyActivity(day: day,
                          activeEnergyKcal: a[day] ?? 0,
                          basalEnergyKcal: b[day] ?? 0,
                          steps: Int(s[day] ?? 0),
                          distanceKm: d[day] ?? 0,
                          flightsClimbed: Int(f[day] ?? 0))
        }
    }

    // MARK: Heart

    func restingHeartRate(in range: DateInterval) async throws -> [SampleValue] {
        try await quantitySamples(.restingHeartRate, unit: HKUnit.count().unitDivided(by: .minute()), in: range)
    }

    func hrv(in range: DateInterval) async throws -> [SampleValue] {
        try await quantitySamples(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), in: range)
    }

    func vo2Max(in range: DateInterval) async throws -> [SampleValue] {
        let unit = HKUnit.literUnit(with: .milli)
            .unitDivided(by: HKUnit.gramUnit(with: .kilo).unitMultiplied(by: .minute()))
        return try await quantitySamples(.vo2Max, unit: unit, in: range)
    }

    // MARK: Workouts

    func workouts(in range: DateInterval) async throws -> [WorkoutSample] {
        let predicate = HKQuery.predicateForSamples(withStart: range.start, end: range.end)
        let workouts: [HKWorkout] = try await withCheckedThrowingContinuation { cont in
            let q = HKSampleQuery(sampleType: .workoutType(), predicate: predicate,
                                  limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error { cont.resume(throwing: error); return }
                cont.resume(returning: (samples as? [HKWorkout]) ?? [])
            }
            store.execute(q)
        }
        return workouts.map {
            let kcal = $0.statistics(for: HKQuantityType(.activeEnergyBurned))?
                .sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
            return WorkoutSample(start: $0.startDate, end: $0.endDate,
                                 activityName: $0.workoutActivityType.displayName,
                                 activeEnergyKcal: kcal, avgHeartRate: nil)
        }
    }

    // MARK: Sleep

    func sleep(in range: DateInterval) async throws -> [SleepSample] {
        guard let type = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else {
            throw HealthError.unsupportedType
        }
        let predicate = HKQuery.predicateForSamples(withStart: range.start, end: range.end)
        let samples: [HKCategorySample] = try await withCheckedThrowingContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: predicate,
                                  limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, s, error in
                if let error { cont.resume(throwing: error); return }
                cont.resume(returning: (s as? [HKCategorySample]) ?? [])
            }
            store.execute(q)
        }

        let cal = Calendar(identifier: .gregorian)
        var byDay: [Date: SleepSampleBuilder] = [:]
        for s in samples {
            let day = cal.startOfDay(for: s.endDate)
            let minutes = Int(s.endDate.timeIntervalSince(s.startDate) / 60)
            byDay[day, default: SleepSampleBuilder()].add(value: s.value, minutes: minutes)
        }
        return byDay.map { $0.value.build(day: $0.key) }.sorted { $0.day < $1.day }
    }

    // MARK: - Query helpers

    private func quantitySamples(_ id: HKQuantityTypeIdentifier, unit: HKUnit,
                                 in range: DateInterval) async throws -> [SampleValue] {
        guard let type = HKQuantityType.quantityType(forIdentifier: id) else { throw HealthError.unsupportedType }
        let predicate = HKQuery.predicateForSamples(withStart: range.start, end: range.end)
        return try await withCheckedThrowingContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: predicate,
                                  limit: HKObjectQueryNoLimit,
                                  sortDescriptors: [.init(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, samples, error in
                if let error { cont.resume(throwing: error); return }
                let out = (samples as? [HKQuantitySample])?.map {
                    SampleValue(date: $0.startDate, value: $0.quantity.doubleValue(for: unit))
                } ?? []
                cont.resume(returning: out)
            }
            store.execute(q)
        }
    }

    private func dailySum(_ id: HKQuantityTypeIdentifier, unit: HKUnit,
                          in range: DateInterval) async throws -> [Date: Double] {
        guard let type = HKQuantityType.quantityType(forIdentifier: id) else { throw HealthError.unsupportedType }
        let cal = Calendar(identifier: .gregorian)
        let anchor = cal.startOfDay(for: range.start)
        let predicate = HKQuery.predicateForSamples(withStart: range.start, end: range.end)
        return try await withCheckedThrowingContinuation { cont in
            let q = HKStatisticsCollectionQuery(quantityType: type, quantitySamplePredicate: predicate,
                                                options: .cumulativeSum, anchorDate: anchor,
                                                intervalComponents: DateComponents(day: 1))
            q.initialResultsHandler = { _, results, error in
                if let error { cont.resume(throwing: error); return }
                var out: [Date: Double] = [:]
                results?.enumerateStatistics(from: range.start, to: range.end) { stat, _ in
                    if let sum = stat.sumQuantity() {
                        out[cal.startOfDay(for: stat.startDate)] = sum.doubleValue(for: unit)
                    }
                }
                cont.resume(returning: out)
            }
            store.execute(q)
        }
    }
}

private struct SleepSampleBuilder {
    var inBed = 0, asleep = 0, deep = 0, rem = 0, core = 0
    mutating func add(value: Int, minutes: Int) {
        switch HKCategoryValueSleepAnalysis(rawValue: value) {
        case .inBed: inBed += minutes
        case .asleepDeep: deep += minutes; asleep += minutes
        case .asleepREM: rem += minutes; asleep += minutes
        case .asleepCore: core += minutes; asleep += minutes
        case .asleepUnspecified, .asleep: asleep += minutes
        default: break
        }
    }
    func build(day: Date) -> SleepSample {
        SleepSample(day: day, inBedMinutes: max(inBed, asleep),
                    asleepMinutes: asleep, deepMinutes: deep, remMinutes: rem, coreMinutes: core)
    }
}


#else

/// Non-Apple build stub so the domain layer compiles cross-platform.
struct HealthKitManager: HealthProvider {
    var isAvailable: Bool { false }
    func requestAuthorization() async throws { throw HealthError.unavailable }
    func bodyMass(in range: DateInterval) async throws -> [BodyMassSample] { [] }
    func bodyFatPercentage(in range: DateInterval) async throws -> [SampleValue] { [] }
    func leanBodyMass(in range: DateInterval) async throws -> [SampleValue] { [] }
    func dailyActivity(in range: DateInterval) async throws -> [DailyActivity] { [] }
    func workouts(in range: DateInterval) async throws -> [WorkoutSample] { [] }
    func sleep(in range: DateInterval) async throws -> [SleepSample] { [] }
    func restingHeartRate(in range: DateInterval) async throws -> [SampleValue] { [] }
    func hrv(in range: DateInterval) async throws -> [SampleValue] { [] }
    func vo2Max(in range: DateInterval) async throws -> [SampleValue] { [] }
}

#endif
