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
}

struct WorkoutSample: Sendable {
    let start: Date
    let end: Date
    let activityName: String
    let activeEnergyKcal: Double
    let avgHeartRate: Double?
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
