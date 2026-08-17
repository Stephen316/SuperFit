import Foundation

// Platform-agnostic health data surface. iOS → AppleHealthProvider (HealthKit).
// Android later → HealthConnectProvider. Domain engines depend only on this.

struct BodyMassSample: Sendable { let date: Date; let kg: Double }
struct SampleValue: Sendable { let date: Date; let value: Double }

struct SleepSample: Sendable {
    let day: Date
    let inBedMinutes: Int
    let asleepMinutes: Int
    let deepMinutes: Int
    let remMinutes: Int
    let coreMinutes: Int
    var bedtime: Date?
    var wakeTime: Date?
}

enum SleepStageKind: Sendable, Equatable {
    case inBed, asleepUnspecified, core, deep, rem

    var isAsleep: Bool { self != .inBed }
    var isSpecificStage: Bool {
        switch self {
        case .core, .deep, .rem: return true
        case .inBed, .asleepUnspecified: return false
        }
    }
}

/// Source-tagged Health sleep interval reduced to platform-independent values,
/// allowing the reconciliation rules to be tested without an HKHealthStore.
struct SleepStageInterval: Sendable {
    let start: Date
    let end: Date
    let stage: SleepStageKind
    let sourceID: String
}

/// Converts overlapping, source-specific intervals into one main sleep record
/// on the wake day. Total sleep uses interval unions across sources, so a phone
/// and watch cannot double the night; stage composition comes from the single
/// source with the richest staged coverage, so conflicting stages are not mixed.
enum SleepIntervalReconciler {
    static let sameNightGap: TimeInterval = 3 * 60 * 60

    static func reconcile(_ raw: [SleepStageInterval],
                          calendar: Calendar = .current) -> [SleepSample] {
        let intervals = raw.filter { $0.end > $0.start }.sorted { $0.start < $1.start }
        guard !intervals.isEmpty else { return [] }

        var clusters: [[SleepStageInterval]] = []
        var current: [SleepStageInterval] = []
        var currentEnd = Date.distantPast
        for interval in intervals {
            if !current.isEmpty,
               interval.start.timeIntervalSince(currentEnd) > sameNightGap {
                clusters.append(current)
                current = []
                currentEnd = .distantPast
            }
            current.append(interval)
            currentEnd = max(currentEnd, interval.end)
        }
        if !current.isEmpty { clusters.append(current) }

        let nights = clusters.compactMap { buildNight($0, calendar: calendar) }
        // The schema stores the main sleep for a wake day, not every nap.
        return Dictionary(grouping: nights, by: \SleepSample.day).values
            .compactMap { $0.max { a, b in a.asleepMinutes < b.asleepMinutes } }
            .sorted { $0.day < $1.day }
    }

    private static func buildNight(_ intervals: [SleepStageInterval],
                                   calendar: Calendar) -> SleepSample? {
        let asleep = intervals.filter(\.stage.isAsleep)
        guard let bedtime = asleep.map(\.start).min(),
              let wakeTime = asleep.map(\.end).max() else { return nil }

        let asleepMinutes = minutes(ofUnion: asleep)
        guard asleepMinutes > 0 else { return nil }
        let inBedMinutes = max(minutes(ofUnion: intervals.filter { $0.stage == .inBed }),
                               asleepMinutes)

        let staged = intervals.filter(\.stage.isSpecificStage)
        let stagedBySource = Dictionary(grouping: staged, by: \SleepStageInterval.sourceID)
        let preferredSource = stagedBySource.max { lhs, rhs in
            let left = minutes(ofUnion: lhs.value)
            let right = minutes(ofUnion: rhs.value)
            if left != right { return left < right }
            return lhs.key > rhs.key
        }?.key
        let selectedStages = preferredSource.map { stagedBySource[$0] ?? [] } ?? []

        return SleepSample(
            day: calendar.startOfDay(for: wakeTime),
            inBedMinutes: inBedMinutes,
            asleepMinutes: asleepMinutes,
            deepMinutes: min(minutes(ofUnion: selectedStages.filter { $0.stage == .deep }),
                             asleepMinutes),
            remMinutes: min(minutes(ofUnion: selectedStages.filter { $0.stage == .rem }),
                            asleepMinutes),
            coreMinutes: min(minutes(ofUnion: selectedStages.filter { $0.stage == .core }),
                             asleepMinutes),
            bedtime: bedtime,
            wakeTime: wakeTime)
    }

    private static func minutes(ofUnion intervals: [SleepStageInterval]) -> Int {
        let sorted = intervals.sorted { $0.start < $1.start }
        guard var start = sorted.first?.start, var end = sorted.first?.end else { return 0 }
        var seconds: TimeInterval = 0
        for interval in sorted.dropFirst() {
            if interval.start <= end {
                end = max(end, interval.end)
            } else {
                seconds += end.timeIntervalSince(start)
                start = interval.start
                end = interval.end
            }
        }
        seconds += end.timeIntervalSince(start)
        return Int((seconds / 60).rounded())
    }
}

/// One lap or split within a workout — a pool length, a manual lap press, or a
/// segment the watch marked itself.
struct WorkoutLapSample: Sendable, Codable, Equatable {
    let index: Int
    let start: Date
    let durationSeconds: Double
    var distanceMetres: Double?
    var avgHeartRate: Double?
}

/// Average heart rate for one measured minute of a workout. Minute buckets
/// preserve interval changes that a single session average smooths away.
struct HeartRateSegment: Sendable, Codable, Equatable {
    let durationMinutes: Double
    let avgHeartRate: Double
}

/// A finished workout with everything the source recorded.
///
/// Every metric past the first four is optional, and stays `nil` when the source
/// didn't measure it. A treadmill run has no elevation and a swim has no power;
/// storing those as 0 would make an absence indistinguishable from a measurement,
/// which is the same failure the recovery engine avoids for sleep efficiency.
struct WorkoutSample: Sendable {
    let externalID: String
    let start: Date
    let end: Date
    let activity: WorkoutActivity
    let activeEnergyKcal: Double

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
    var laps: [WorkoutLapSample] = []
    var heartRateSegments: [HeartRateSegment] = []
    /// Device or app that recorded it — "Apple Watch", "Garmin Connect".
    var sourceName: String?
    /// Bundle identifier of the app that wrote the workout. Lets the importer
    /// recognise — and skip — the workouts SuperFit itself wrote to HealthKit,
    /// which would otherwise re-import as duplicates of sessions it already has.
    var sourceBundleID: String?

    var durationSeconds: Double { end.timeIntervalSince(start) }
}

/// A workout SuperFit tracked itself, described for writing back to HealthKit so
/// it shows up in Apple Health and the Fitness app. Only what SuperFit actually
/// measured is carried; an absent value is written as no sample, never a zero.
struct WorkoutWrite: Sendable {
    let start: Date
    let end: Date
    let activity: WorkoutActivity
    var activeEnergyKcal: Double?
    var distanceMetres: Double?
}

struct DailyActivity: Sendable {
    let day: Date
    let activeEnergyKcal: Double
    let basalEnergyKcal: Double
    let steps: Int
    let distanceKm: Double
    let flightsClimbed: Int
}

protocol HealthProvider: Sendable {
    var isAvailable: Bool { get }
    func requestAuthorization() async throws
    func bodyMass(in range: DateInterval) async throws -> [BodyMassSample]
    func bodyFatPercentage(in range: DateInterval) async throws -> [SampleValue]
    func leanBodyMass(in range: DateInterval) async throws -> [SampleValue]
    func dailyActivity(in range: DateInterval) async throws -> [DailyActivity]
    func workouts(in range: DateInterval) async throws -> [WorkoutSample]
    func sleep(in range: DateInterval) async throws -> [SleepSample]
    func restingHeartRate(in range: DateInterval) async throws -> [SampleValue]
    func hrv(in range: DateInterval) async throws -> [SampleValue]
    func vo2Max(in range: DateInterval) async throws -> [SampleValue]
    /// Writes a SuperFit-tracked workout to HealthKit so it appears in Apple
    /// Health/Fitness. Providers that can't write (the non-Apple stub, test
    /// doubles, Garmin) inherit the no-op default below.
    func saveWorkout(_ write: WorkoutWrite) async throws
}

extension HealthProvider {
    func saveWorkout(_ write: WorkoutWrite) async throws {}
}
