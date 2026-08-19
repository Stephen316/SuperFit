import Foundation
import Observation
import WatchKit
// HealthKit isn't fully Sendable-audited; @preconcurrency keeps its async calls
// from the main actor warning under strict concurrency (the calls are safe).
@preconcurrency import HealthKit

/// Runs a strength workout on the watch and drives the HR-based rest flow (#26).
///
/// - Starts an `HKWorkoutSession` + `HKLiveWorkoutBuilder` so the watch captures
///   live heart rate and energy, and **mirrors** the session to the phone via
///   `startMirroringToCompanionDevice()`. The phone's `WatchWorkoutMonitor`
///   already receives the `{"hr","kcal"}` stream and logs the finished workout.
/// - Between sets, `HRRestAdvisor` decides when HR has recovered enough to lift
///   again; the HR the user actually resumes at is recorded for future learning.
///
/// Set/rep logging stays on the phone; the watch owns the session and the timer.
@MainActor
@Observable
final class WatchWorkoutManager: NSObject, HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {

    enum Phase { case idle, working, resting, ended }

    private(set) var phase: Phase = .idle
    private(set) var currentHR: Double = 0
    private(set) var activeEnergyKcal: Double = 0
    private(set) var elapsed: TimeInterval = 0

    // Rest state (#26)
    private(set) var restElapsed: TimeInterval = 0
    private(set) var setPeakHR: Double = 0
    private(set) var readiness: HRRestAdvisor.Readiness = .resting
    private(set) var learnedResumeHR: Double?
    var targetHR: Double { advisor.targetHR(peakHR: setPeakHR, baselineHR: baselineHR) }

    private let advisor = HRRestAdvisor()
    private let resumeStore = ResumeHRStore()
    private var baselineHR: Double?

    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var workoutStart: Date?
    private var restStart: Date?

    // MARK: Lifecycle

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let share: Set<HKSampleType> = [
            HKQuantityType.workoutType(),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.heartRate),
        ]
        let read: Set<HKObjectType> = [
            HKQuantityType(.heartRate),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.restingHeartRate),
            HKObjectType.workoutType(),
        ]
        try? await healthStore.requestAuthorization(toShare: share, read: read)
        baselineHR = await latestRestingHR()
        learnedResumeHR = resumeStore.learnedResumeHR()
    }

    func startWorkout() async {
        let config = HKWorkoutConfiguration()
        config.activityType = .traditionalStrengthTraining
        config.locationType = .indoor

        guard let session = try? HKWorkoutSession(healthStore: healthStore, configuration: config)
        else { return }
        let builder = session.associatedWorkoutBuilder()
        builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore,
                                                     workoutConfiguration: config)
        session.delegate = self
        builder.delegate = self
        self.session = session
        self.builder = builder

        let start = Date()
        session.startActivity(with: start)
        try? await builder.beginCollection(at: start)
        try? await session.startMirroringToCompanionDevice()

        workoutStart = start
        setPeakHR = 0
        phase = .working
    }

    /// End of a set → begin rest. The set's peak HR (tracked while working) is
    /// what the advisor recovers from.
    func doneSet() {
        guard phase == .working else { return }
        restStart = Date()
        restElapsed = 0
        readiness = .resting
        phase = .resting
    }

    /// Start of the next set. Records the HR the user resumed at (for learning),
    /// then resets peak tracking for the new set.
    func startNextSet() {
        guard phase == .resting else { return }
        if currentHR > 0 {
            resumeStore.record(currentHR)
            learnedResumeHR = resumeStore.learnedResumeHR()
        }
        restStart = nil
        setPeakHR = 0
        phase = .working
    }

    func endWorkout() async {
        guard let session, let builder else { phase = .ended; return }
        let end = Date()
        session.end()
        try? await builder.endCollection(at: end)
        _ = try? await builder.finishWorkout()
        phase = .ended
    }

    func reset() {
        session = nil
        builder = nil
        workoutStart = nil
        restStart = nil
        currentHR = 0
        activeEnergyKcal = 0
        elapsed = 0
        restElapsed = 0
        setPeakHR = 0
        readiness = .resting
        phase = .idle
    }

    /// Called once a second from the view: advances the clocks and re-evaluates
    /// readiness, buzzing once when a rest crosses into "ready".
    func tick() {
        if phase == .working, let start = workoutStart {
            elapsed = Date().timeIntervalSince(start)
        }
        guard phase == .resting, let start = restStart else { return }
        restElapsed = Date().timeIntervalSince(start)
        let next = advisor.readiness(currentHR: currentHR > 0 ? currentHR : nil,
                                     peakHR: setPeakHR, baselineHR: baselineHR,
                                     elapsed: restElapsed)
        if next == .ready && readiness == .resting {
            WKInterfaceDevice.current().play(.success)
        }
        readiness = next
    }

    // MARK: HK delegates (nonisolated — hop to the main actor to touch state)

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder,
                                    didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let hr = Self.mostRecent(workoutBuilder, .heartRate, collectedTypes,
                                 unit: .count().unitDivided(by: .minute()))
        let kcal = Self.sum(workoutBuilder, .activeEnergyBurned, collectedTypes,
                            unit: .kilocalorie())
        Task { @MainActor in self.apply(hr: hr, kcal: kcal) }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession,
                                    didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState, date: Date) {
        if toState == .ended || toState == .stopped {
            Task { @MainActor in self.phase = .ended }
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession,
                                    didFailWithError error: Error) {
        Task { @MainActor in self.phase = .ended }
    }

    // MARK: Private

    private func apply(hr: Double?, kcal: Double?) {
        if let hr, hr > 0 {
            currentHR = hr
            if phase == .working { setPeakHR = max(setPeakHR, hr) }
        }
        if let kcal { activeEnergyKcal = kcal }
        sendToPhone()
    }

    private func sendToPhone() {
        guard let session else { return }
        let payload: [String: Double] = ["hr": currentHR, "kcal": activeEnergyKcal]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        Task { try? await session.sendToRemoteWorkoutSession(data: data) }
    }

    private func latestRestingHR() async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) else { return nil }
        return await withCheckedContinuation { cont in
            let sort = [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
            let query = HKSampleQuery(sampleType: type, predicate: nil, limit: 1,
                                      sortDescriptors: sort) { _, samples, _ in
                let bpm = (samples?.first as? HKQuantitySample)?
                    .quantity.doubleValue(for: .count().unitDivided(by: .minute()))
                cont.resume(returning: bpm)
            }
            healthStore.execute(query)
        }
    }

    private nonisolated static func mostRecent(_ builder: HKLiveWorkoutBuilder,
                                               _ id: HKQuantityTypeIdentifier,
                                               _ collected: Set<HKSampleType>,
                                               unit: HKUnit) -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: id),
              collected.contains(type) else { return nil }
        return builder.statistics(for: type)?.mostRecentQuantity()?.doubleValue(for: unit)
    }

    private nonisolated static func sum(_ builder: HKLiveWorkoutBuilder,
                                        _ id: HKQuantityTypeIdentifier,
                                        _ collected: Set<HKSampleType>,
                                        unit: HKUnit) -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: id),
              collected.contains(type) else { return nil }
        return builder.statistics(for: type)?.sumQuantity()?.doubleValue(for: unit)
    }
}
