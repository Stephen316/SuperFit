import Foundation

/// Overnight recovery metrics, from whichever provider supplies them.
/// Garmin exposes HRV status and staged sleep that Apple Health never receives
/// from Garmin Connect; when a Garmin account is linked its values win.
struct RecoveryMetrics: Sendable {
    let day: Date
    var hrvSDNN: Double?
    var restingHR: Double?
    var sleep: SleepSample?
    var bodyBattery: Int?
}

/// Anything that can supply overnight recovery metrics. HealthKit implements it
/// implicitly via SyncCoordinator; Garmin implements it over the network.
protocol RecoveryProvider: Sendable {
    var isLinked: Bool { get async }
    func recoveryMetrics(in range: DateInterval) async throws -> [RecoveryMetrics]
}
