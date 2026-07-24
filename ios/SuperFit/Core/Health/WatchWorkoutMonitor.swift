import Foundation
#if canImport(HealthKit)
import HealthKit
#endif

struct LiveWorkoutInfo: Sendable, Equatable {
    let activityName: String
    let startedAt: Date
    let heartRate: Double?
    let activeEnergyKcal: Double
}

#if canImport(HealthKit)

/// Surfaces watch workouts in the app.
///
/// Two tiers:
/// 1. **Live mirroring** (`workoutSessionMirroringStartHandler`) — streams a
///    running session's metrics in real time. HealthKit only mirrors sessions
///    started by *our own* watchOS companion app, so this activates when the
///    watch app ships; the plumbing is ready now.
/// 2. **Finished-workout observation** — an HKObserverQuery fires the moment
///    any workout (including from Apple's built-in Workout app) is saved, so
///    watch workouts appear in the app seconds after they end. Apple does not
///    expose other apps' in-progress sessions; this is the platform limit.
@MainActor
@Observable
final class WatchWorkoutMonitor {

    private(set) var liveWorkout: LiveWorkoutInfo?
    private(set) var todaysWorkouts: [WorkoutSample] = []

    private let store = HKHealthStore()
    private let provider: any HealthProvider
    private var observerQuery: HKObserverQuery?

    init(provider: any HealthProvider = HealthKitManager()) {
        self.provider = provider
    }

    func start() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        installMirroringHandler()
        installFinishedWorkoutObserver()
        await refreshTodaysWorkouts()
    }

    func refreshTodaysWorkouts() async {
        let start = Calendar.current.startOfDay(for: .now)
        let range = DateInterval(start: start, end: .now)
        todaysWorkouts = (try? await provider.workouts(in: range)) ?? []
    }

    private func installMirroringHandler() {
        store.workoutSessionMirroringStartHandler = { [weak self] session in
            Task { @MainActor in
                self?.attach(session)
            }
        }
    }

    private func attach(_ session: HKWorkoutSession) {
        liveWorkout = LiveWorkoutInfo(activityName: session.workoutConfiguration.activityType.displayName,
                                      startedAt: session.startDate ?? .now,
                                      heartRate: nil,
                                      activeEnergyKcal: 0)
        let handler = MirroredSessionHandler { [weak self] update in
            Task { @MainActor in
                guard let self, let current = self.liveWorkout else { return }
                self.liveWorkout = LiveWorkoutInfo(activityName: current.activityName,
                                                   startedAt: current.startedAt,
                                                   heartRate: update.heartRate ?? current.heartRate,
                                                   activeEnergyKcal: update.energy ?? current.activeEnergyKcal)
                if update.ended {
                    self.liveWorkout = nil
                    await self.refreshTodaysWorkouts()
                }
            }
        }
        session.delegate = handler
        objc_setAssociatedObject(session, &MirroredSessionHandler.key, handler, .OBJC_ASSOCIATION_RETAIN)
    }

    private func installFinishedWorkoutObserver() {
        guard observerQuery == nil else { return }
        let query = HKObserverQuery(sampleType: .workoutType(), predicate: nil) { [weak self] _, completion, _ in
            Task { @MainActor in
                await self?.refreshTodaysWorkouts()
                completion()
            }
        }
        observerQuery = query
        store.execute(query)
    }
}

/// HKWorkoutSessionDelegate must be an NSObject; kept tiny and forwarding.
private final class MirroredSessionHandler: NSObject, HKWorkoutSessionDelegate {
    struct Update {
        var heartRate: Double?
        var energy: Double?
        var ended = false
    }

    static var key: UInt8 = 0
    private let onUpdate: (Update) -> Void

    init(onUpdate: @escaping (Update) -> Void) {
        self.onUpdate = onUpdate
    }

    func workoutSession(_ session: HKWorkoutSession,
                        didChangeTo toState: HKWorkoutSessionState,
                        from fromState: HKWorkoutSessionState, date: Date) {
        if toState == .ended || toState == .stopped {
            onUpdate(Update(ended: true))
        }
    }

    func workoutSession(_ session: HKWorkoutSession, didFailWithError error: Error) {
        onUpdate(Update(ended: true))
    }

    func workoutSession(_ session: HKWorkoutSession,
                        didReceiveDataFromRemoteWorkoutSession data: [Data]) {
        var update = Update()
        for blob in data {
            guard let dict = try? JSONSerialization.jsonObject(with: blob) as? [String: Double] else { continue }
            update.heartRate = dict["hr"] ?? update.heartRate
            update.energy = dict["kcal"] ?? update.energy
        }
        onUpdate(update)
    }
}

extension HKWorkoutActivityType {
    var displayName: String {
        switch self {
        case .traditionalStrengthTraining, .functionalStrengthTraining: return "Strength"
        case .running: return "Running"
        case .cycling: return "Cycling"
        case .walking: return "Walking"
        case .highIntensityIntervalTraining: return "HIIT"
        case .swimming: return "Swimming"
        case .rowing: return "Rowing"
        default: return "Workout"
        }
    }
}

#else

@MainActor
@Observable
final class WatchWorkoutMonitor {
    private(set) var liveWorkout: LiveWorkoutInfo?
    private(set) var todaysWorkouts: [WorkoutSample] = []
    func start() async {}
    func refreshTodaysWorkouts() async {}
}

#endif
