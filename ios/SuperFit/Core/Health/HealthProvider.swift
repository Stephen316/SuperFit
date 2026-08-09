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

    var durationSeconds: Double { end.timeIntervalSince(start) }
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
}
