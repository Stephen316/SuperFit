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
        // Workout detail: distance per modality, elevation, cadence, power and
        // swim strokes are separate quantity types, not fields on HKWorkout.
        q(.distanceCycling); q(.distanceSwimming); q(.distanceDownhillSnowSports)
        q(.swimmingStrokeCount); q(.flightsClimbed)
        if #available(iOS 16.0, *) {
            q(.runningPower); q(.runningSpeed); q(.runningStrideLength)
            q(.cyclingPower); q(.cyclingCadence); q(.cyclingSpeed)
        }
        if #available(iOS 17.0, *) { q(.timeInDaylight) }
        q(.stepCount)
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
        var out: [WorkoutSample] = []
        for workout in workouts {
            out.append(await sample(from: workout))
        }
        return out
    }

    /// Assembles everything HealthKit knows about one workout.
    ///
    /// Statistics come off the workout itself where they exist; heart rate needs
    /// a separate query because `HKWorkout` carries no HR statistics of its own.
    /// Anything the source didn't record stays nil rather than becoming zero.
    private func sample(from workout: HKWorkout) async -> WorkoutSample {
        func stat(_ id: HKQuantityTypeIdentifier, _ unit: HKUnit) -> Double? {
            workout.statistics(for: HKQuantityType(id))?
                .sumQuantity()?.doubleValue(for: unit)
        }

        let meta = workout.metadata ?? [:]
        let isIndoor = meta[HKMetadataKeyIndoorWorkout] as? Bool
        let swimsInPool = (meta[HKMetadataKeySwimmingLocationType] as? Int)
            .map { $0 == HKWorkoutSwimmingLocationType.pool.rawValue }
        let activity = WorkoutActivity(healthKit: workout.workoutActivityType,
                                       isIndoor: isIndoor, swimsInPool: swimsInPool)

        // Distance lives under a different type per modality, so ask for the one
        // this activity would have written and fall back through the others.
        let distance = stat(.distanceWalkingRunning, .meter())
            ?? stat(.distanceCycling, .meter())
            ?? stat(.distanceSwimming, .meter())
            ?? stat(.distanceDownhillSnowSports, .meter())

        var s = WorkoutSample(
            externalID: workout.uuid.uuidString,
            start: workout.startDate,
            end: workout.endDate,
            activity: activity,
            activeEnergyKcal: stat(.activeEnergyBurned, .kilocalorie()) ?? 0)

        s.distanceMetres = distance
        s.swimStrokeCount = stat(.swimmingStrokeCount, .count())
        s.sourceName = workout.sourceRevision.source.name
        s.elevationGainMetres = (meta[HKMetadataKeyElevationAscended] as? HKQuantity)?
            .doubleValue(for: .meter())
        s.swimStrokeStyle = (meta[HKMetadataKeySwimmingStrokeStyle] as? Int)
            .flatMap(strokeStyleName)

        if let hr = try? await heartRateStatistics(in: DateInterval(start: workout.startDate,
                                                                   end: workout.endDate)) {
            s.avgHeartRate = hr.average
            s.maxHeartRate = hr.maximum
            s.minHeartRate = hr.minimum
        }

        // Cadence as a rate can't be summed, so derive it from step count over
        // the duration for foot activities. Cycling reports its own.
        if activity.metrics.contains(.cadence), workout.duration > 0 {
            if let steps = stat(.stepCount, .count()) {
                s.avgCadence = steps / (workout.duration / 60)
            }
        }

        s.laps = laps(from: workout)
        return s
    }

    private func strokeStyleName(_ raw: Int) -> String? {
        switch HKSwimmingStrokeStyle(rawValue: raw) {
        case .freestyle: return "Freestyle"
        case .backstroke: return "Backstroke"
        case .breaststroke: return "Breaststroke"
        case .butterfly: return "Butterfly"
        case .mixed: return "Mixed"
        case .kickboard: return "Kickboard"
        default: return nil
        }
    }

    /// Laps from the workout's own segment/lap markers.
    private func laps(from workout: HKWorkout) -> [WorkoutLapSample] {
        guard let events = workout.workoutEvents else { return [] }
        let marks = events.filter { $0.type == .lap || $0.type == .segment }
        return marks.enumerated().map { i, event in
            WorkoutLapSample(index: i + 1,
                             start: event.dateInterval.start,
                             durationSeconds: event.dateInterval.duration,
                             distanceMetres: nil,
                             avgHeartRate: nil)
        }
    }

    /// Average, max and min heart rate over an interval.
    ///
    /// `HKStatisticsQuery` with `.discreteAverage` does this server-side rather
    /// than pulling every beat sample across the whole workout.
    private func heartRateStatistics(
        in range: DateInterval
    ) async throws -> (average: Double?, maximum: Double?, minimum: Double?) {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            throw HealthError.unsupportedType
        }
        let predicate = HKQuery.predicateForSamples(withStart: range.start, end: range.end)
        return try await withCheckedThrowingContinuation { cont in
            let q = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate,
                                      options: [.discreteAverage, .discreteMax, .discreteMin]) { _, stats, error in
                if let error { cont.resume(throwing: error); return }
                let unit = HKUnit.count().unitDivided(by: .minute())
                cont.resume(returning: (stats?.averageQuantity()?.doubleValue(for: unit),
                                        stats?.maximumQuantity()?.doubleValue(for: unit),
                                        stats?.minimumQuantity()?.doubleValue(for: unit)))
            }
            store.execute(q)
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
            byDay[day, default: SleepSampleBuilder()].add(value: s.value, minutes: minutes,
                                                          start: s.startDate, end: s.endDate)
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
    /// Bounds of the asleep segments only — `inBed` brackets the night more
    /// loosely (reading, lying awake) and would blur bedtime consistency.
    var firstAsleep: Date?
    var lastAsleep: Date?

    mutating func add(value: Int, minutes: Int, start: Date, end: Date) {
        switch HKCategoryValueSleepAnalysis(rawValue: value) {
        case .inBed:
            inBed += minutes
            return
        case .asleepDeep: deep += minutes; asleep += minutes
        case .asleepREM: rem += minutes; asleep += minutes
        case .asleepCore: core += minutes; asleep += minutes
        case .asleepUnspecified, .asleep: asleep += minutes
        default: return
        }
        firstAsleep = min(start, firstAsleep ?? start)
        lastAsleep = max(end, lastAsleep ?? end)
    }

    func build(day: Date) -> SleepSample {
        SleepSample(day: day, inBedMinutes: max(inBed, asleep),
                    asleepMinutes: asleep, deepMinutes: deep, remMinutes: rem, coreMinutes: core,
                    bedtime: firstAsleep, wakeTime: lastAsleep)
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
