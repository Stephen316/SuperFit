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

    /// What the app writes back: the workout itself plus the energy and distance
    /// samples that make it read as a real session in Apple Fitness. Kept as
    /// narrow as the write path actually uses — no HR, since an iPhone-only
    /// session records none.
    private var shareTypes: Set<HKSampleType> {
        var t: Set<HKSampleType> = [HKObjectType.workoutType()]
        func q(_ id: HKQuantityTypeIdentifier) { if let x = HKQuantityType.quantityType(forIdentifier: id) { t.insert(x) } }
        q(.activeEnergyBurned)
        q(.distanceWalkingRunning); q(.distanceCycling); q(.distanceSwimming)
        return t
    }

    func requestAuthorization() async throws {
        guard isAvailable else { throw HealthError.unavailable }
        try await store.requestAuthorization(toShare: shareTypes, read: readTypes)
    }

    // MARK: Write-back

    /// Saves a SuperFit-tracked workout to HealthKit via `HKWorkoutBuilder`, so a
    /// run or ride started in the app lands in Apple Health and Fitness alongside
    /// watch workouts. Returns quietly when HealthKit is unavailable, the
    /// interval is empty, or the user hasn't granted write access — the builder
    /// throws in the last case and the caller treats a failed write as best-effort.
    func saveWorkout(_ write: WorkoutWrite) async throws {
        guard isAvailable, write.end > write.start else { return }

        let config = HKWorkoutConfiguration()
        config.activityType = write.activity.healthKitType

        let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())
        try await builder.beginCollection(at: write.start)

        var samples: [HKSample] = []
        if let kcal = write.activeEnergyKcal, kcal > 0,
           let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
            let qty = HKQuantity(unit: .kilocalorie(), doubleValue: kcal)
            samples.append(HKQuantitySample(type: energyType, quantity: qty,
                                            start: write.start, end: write.end))
        }
        if let metres = write.distanceMetres, metres > 0,
           let distanceID = distanceIdentifier(for: config.activityType),
           let distanceType = HKQuantityType.quantityType(forIdentifier: distanceID) {
            let qty = HKQuantity(unit: .meter(), doubleValue: metres)
            samples.append(HKQuantitySample(type: distanceType, quantity: qty,
                                            start: write.start, end: write.end))
        }
        if !samples.isEmpty { try await builder.addSamples(samples) }

        try await builder.endCollection(at: write.end)
        _ = try await builder.finishWorkout()
    }

    /// Distance is a per-modality quantity type in HealthKit; only the activities
    /// SuperFit can measure a distance for map to one.
    private func distanceIdentifier(for type: HKWorkoutActivityType) -> HKQuantityTypeIdentifier? {
        switch type {
        case .running, .walking, .hiking: return .distanceWalkingRunning
        case .cycling: return .distanceCycling
        case .swimming: return .distanceSwimming
        default: return nil
        }
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
        // Each workout needs a separate server-side heart-rate statistics
        // query. Running those strictly one after another made a 90-day import
        // pay the HealthKit round-trip once per workout. Keep four in flight —
        // enough to hide query latency without flooding HKHealthStore — and
        // restore the source order before returning.
        return await withTaskGroup(of: (Int, WorkoutSample).self) { group in
            let limit = min(4, workouts.count)
            var next = 0
            for _ in 0..<limit {
                let index = next
                let workout = workouts[index]
                group.addTask { (index, await self.sample(from: workout)) }
                next += 1
            }

            var results: [(Int, WorkoutSample)] = []
            results.reserveCapacity(workouts.count)
            while let result = await group.next() {
                results.append(result)
                if next < workouts.count {
                    let index = next
                    let workout = workouts[index]
                    group.addTask { (index, await self.sample(from: workout)) }
                    next += 1
                }
            }
            return results.sorted { $0.0 < $1.0 }.map(\.1)
        }
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
        s.sourceBundleID = workout.sourceRevision.source.bundleIdentifier
        s.elevationGainMetres = (meta[HKMetadataKeyElevationAscended] as? HKQuantity)?
            .doubleValue(for: .meter())
        s.swimStrokeStyle = (meta[HKMetadataKeySwimmingStrokeStyle] as? Int)
            .flatMap(strokeStyleName)

        if let hr = try? await heartRateStatistics(for: workout) {
            s.avgHeartRate = hr.average
            s.maxHeartRate = hr.maximum
            s.minHeartRate = hr.minimum
            s.heartRateSegments = hr.segments
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

    /// Average, max and min heart rate over an interval, plus minute buckets for
    /// load calculations. The workout-association predicate is essential: a
    /// time-only query mixes concurrent streams from other devices and apps.
    private func heartRateStatistics(
        for workout: HKWorkout
    ) async throws -> (average: Double?, maximum: Double?, minimum: Double?,
                       segments: [HeartRateSegment]) {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            throw HealthError.unsupportedType
        }
        let time = HKQuery.predicateForSamples(withStart: workout.startDate, end: workout.endDate)
        let associated = NSCompoundPredicate(andPredicateWithSubpredicates: [
            time, HKQuery.predicateForObjects(from: workout)
        ])
        var samples = try await heartRateSamples(type: type, predicate: associated)

        // Some third-party stores do not attach their HR samples to the workout.
        // Fall back only to the workout's own source/device, never every stream
        // that happened to overlap in time.
        if samples.isEmpty {
            var predicates: [NSPredicate] = [
                time, HKQuery.predicateForObjects(from: workout.sourceRevision.source)
            ]
            if let device = workout.device {
                predicates.append(HKQuery.predicateForObjects(from: Set([device])))
            }
            samples = try await heartRateSamples(
                type: type,
                predicate: NSCompoundPredicate(andPredicateWithSubpredicates: predicates))
        }

        let unit = HKUnit.count().unitDivided(by: .minute())
        let values = samples.map { $0.quantity.doubleValue(for: unit) }
        guard !values.isEmpty else { return (nil, nil, nil, []) }
        let calendar = Calendar(identifier: .gregorian)
        let buckets = Dictionary(grouping: samples) {
            calendar.dateInterval(of: .minute, for: $0.startDate)?.start ?? $0.startDate
        }
        let segments = buckets.keys.sorted().compactMap { minute -> HeartRateSegment? in
            guard let bucket = buckets[minute], !bucket.isEmpty else { return nil }
            let average = bucket.reduce(0.0) {
                $0 + $1.quantity.doubleValue(for: unit)
            } / Double(bucket.count)
            return HeartRateSegment(durationMinutes: 1, avgHeartRate: average)
        }
        return (values.reduce(0, +) / Double(values.count), values.max(), values.min(), segments)
    }

    private func heartRateSamples(type: HKQuantityType,
                                  predicate: NSPredicate) async throws -> [HKQuantitySample] {
        return try await withCheckedThrowingContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: predicate,
                                  limit: HKObjectQueryNoLimit,
                                  sortDescriptors: [.init(key: HKSampleSortIdentifierStartDate,
                                                          ascending: true)]) { _, raw, error in
                if let error { cont.resume(throwing: error); return }
                cont.resume(returning: (raw as? [HKQuantitySample]) ?? [])
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

        let intervals = samples.compactMap { sample -> SleepStageInterval? in
            let stage: SleepStageKind
            switch HKCategoryValueSleepAnalysis(rawValue: sample.value) {
            case .inBed: stage = .inBed
            case .asleepDeep: stage = .deep
            case .asleepREM: stage = .rem
            case .asleepCore: stage = .core
            case .asleepUnspecified, .asleep: stage = .asleepUnspecified
            default: return nil
            }
            let device = sample.device?.localIdentifier ?? sample.device?.name ?? "unknown-device"
            let source = sample.sourceRevision.source.bundleIdentifier
            return SleepStageInterval(start: sample.startDate, end: sample.endDate,
                                      stage: stage, sourceID: "\(source)|\(device)")
        }
        return SleepIntervalReconciler.reconcile(
            intervals, calendar: Calendar(identifier: .gregorian))
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
