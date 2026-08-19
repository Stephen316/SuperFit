import Foundation
import SwiftData

/// Brings finished workouts from the health sources into SwiftData.
///
/// Split out from `SyncCoordinator` because workouts are event-keyed rather than
/// day-keyed: everything else upserts one row per calendar day, whereas a day can
/// hold any number of workouts and each needs its own identity to stay
/// idempotent. `WorkoutImporter` owns the rules; this owns the store.
@MainActor
final class WorkoutSyncService {
    private let health: any HealthProvider
    private let garmin: GarminProvider?
    private let context: ModelContext

    init(health: any HealthProvider = HealthKitManager(),
         garmin: GarminProvider? = GarminProvider(),
         context: ModelContext) {
        self.health = health
        self.garmin = garmin
        self.context = context
    }

    @discardableResult
    func sync(days: Int = 90) async -> Int {
        guard health.isAvailable else { return 0 }
        let range = DateInterval(start: .now.addingTimeInterval(-Double(days) * 86_400),
                                 end: .now)
        guard let samples = try? await health.workouts(in: range) else { return 0 }

        let sampleRange = storageRange(starts: samples.map(\.start),
                                       ends: samples.map(\.end), fallback: range)
        var imported = apply(samples, in: sampleRange)

        // Garmin second, enriching what HealthKit already brought in. Garmin
        // Connect writes workouts to Apple Health but drops its own metrics on
        // the way — training effect and running dynamics have no HealthKit
        // equivalent — so the backend fills those in against the same workout
        // rather than creating a parallel copy.
        if let garmin, await garmin.isLinked,
           let enriched = try? await garmin.workouts(in: range) {
            let garminRange = storageRange(starts: enriched.map(\.start),
                                           ends: enriched.map(\.end), fallback: range)
            imported += applyGarmin(enriched, in: garminRange)
        }

        try? context.save()
        return imported
    }

    /// Applies importer decisions to the store. Returns the number of new rows.
    @discardableResult
    func apply(_ samples: [WorkoutSample]) -> Int {
        guard let first = samples.map(\.start).min(),
              let last = samples.map(\.end).max() else { return 0 }
        let range = DateInterval(start: first, end: max(last, first.addingTimeInterval(1)))
        return apply(samples, in: range)
    }

    private func storageRange(starts: [Date], ends: [Date],
                              fallback: DateInterval) -> DateInterval {
        guard let first = starts.min(), let last = ends.max() else { return fallback }
        return DateInterval(start: first, end: max(last, first.addingTimeInterval(1)))
    }

    private func apply(_ samples: [WorkoutSample], in range: DateInterval) -> Int {
        // Workouts SuperFit wrote to HealthKit itself come back through the same
        // observer. Re-importing them would duplicate a session the app already
        // stored, so drop anything this app authored before deciding.
        let samples = samples.filter { $0.sourceBundleID != Bundle.main.bundleIdentifier }
        let existing = fetchRecords(in: range)
        var byExternalID = Dictionary(
            existing.compactMap { r in r.externalID.map { ($0, r) } },
            uniquingKeysWith: { a, _ in a })

        let decisions = WorkoutImporter.decide(
            samples: samples,
            existingExternalIDs: Set(byExternalID.keys))

        var inserted = 0
        var claimedDeviceRecords: Set<UUID> = []
        for (sample, decision) in zip(samples, decisions) {
            // A cardio session tracked in SuperFit and the Watch copy written to
            // HealthKit carry different IDs. Join them by activity and shared
            // time, retaining one row with phone RPE/location plus Watch HR.
            if !sample.activity.isStrength,
               let device = matchingDeviceRecord(for: sample, in: existing,
                                                  excluding: claimedDeviceRecords) {
                if let imported = byExternalID[decision.externalID], imported !== device {
                    if device.sessionRPE == nil { device.sessionRPE = imported.sessionRPE }
                    context.delete(imported)
                }
                merge(sample, intoDeviceRecord: device)
                device.externalID = decision.externalID
                byExternalID[decision.externalID] = device
                claimedDeviceRecords.insert(device.id)
                continue
            }

            switch decision.action {
            case .skipDuplicateInBatch:
                continue
            case .update:
                if let record = byExternalID[decision.externalID] {
                    write(sample, into: record)
                }
            case .insert:
                let record = WorkoutRecord(startedAt: sample.start, endedAt: sample.end,
                                           activity: sample.activity, source: .appleHealth)
                record.externalID = sample.externalID
                write(sample, into: record)
                context.insert(record)
                byExternalID[decision.externalID] = record
                inserted += 1
            }
        }
        return inserted
    }

    private func matchingDeviceRecord(for sample: WorkoutSample,
                                      in records: [WorkoutRecord],
                                      excluding claimed: Set<UUID>) -> WorkoutRecord? {
        guard sample.end > sample.start else { return nil }
        let candidates = records.filter {
            $0.source == .liveSession && $0.activity == sample.activity
                && $0.durationSeconds > 0 && !claimed.contains($0.id)
        }
        let match = WorkoutTimeMatcher.matches(
            workouts: [DateInterval(start: sample.start, end: sample.end)],
            sessions: candidates.map { DateInterval(start: $0.startedAt, end: $0.endedAt) })
        guard let index = match[0] else { return nil }
        return candidates[index]
    }

    private func merge(_ sample: WorkoutSample, intoDeviceRecord record: WorkoutRecord) {
        let start = min(record.startedAt, sample.start)
        let end = max(record.endedAt, sample.end)
        let activeEnergy = record.activeEnergyKcal
        let totalEnergy = record.totalEnergyKcal
        let distance = record.distanceMetres
        let elevation = record.elevationGainMetres
        let cadence = record.avgCadence
        let power = record.avgPowerWatts
        let source = sample.sourceName ?? "Apple Watch"

        write(sample, into: record)
        record.startedAt = start
        record.endedAt = end
        if record.activeEnergyKcal <= 0 { record.activeEnergyKcal = activeEnergy }
        record.totalEnergyKcal = record.totalEnergyKcal ?? totalEnergy
        record.distanceMetres = record.distanceMetres ?? distance
        record.elevationGainMetres = record.elevationGainMetres ?? elevation
        record.avgCadence = record.avgCadence ?? cadence
        record.avgPowerWatts = record.avgPowerWatts ?? power
        record.sourceName = "iPhone + \(source)"
    }

    private func write(_ sample: WorkoutSample, into record: WorkoutRecord) {
        record.startedAt = sample.start
        record.endedAt = sample.end
        record.activity = sample.activity
        record.activeEnergyKcal = sample.activeEnergyKcal
        record.totalEnergyKcal = sample.totalEnergyKcal
        record.distanceMetres = sample.distanceMetres
        record.avgHeartRate = sample.avgHeartRate
        record.maxHeartRate = sample.maxHeartRate
        record.minHeartRate = sample.minHeartRate
        record.elevationGainMetres = sample.elevationGainMetres
        record.avgCadence = sample.avgCadence
        record.avgPowerWatts = sample.avgPowerWatts
        record.swimStrokeCount = sample.swimStrokeCount
        record.swimStrokeStyle = sample.swimStrokeStyle
        record.sourceName = sample.sourceName
        if !sample.laps.isEmpty { record.laps = sample.laps }
        if !sample.heartRateSegments.isEmpty {
            record.heartRateSegments = sample.heartRateSegments
        }
    }

    /// Fills Garmin-only fields onto workouts already imported from HealthKit,
    /// matched on start time rather than identifier: the two systems assign their
    /// own IDs to the same activity.
    private func applyGarmin(_ enriched: [GarminWorkout], in range: DateInterval) -> Int {
        let records = fetchRecords(in: range)
        var added = 0
        for item in enriched {
            guard let match = records.min(by: {
                abs($0.startedAt.timeIntervalSince(item.start))
                    < abs($1.startedAt.timeIntervalSince(item.start))
            }), abs(match.startedAt.timeIntervalSince(item.start)) < 120 else {
                // No HealthKit counterpart — Garmin Connect wasn't syncing to
                // Apple Health at the time, so the backend copy is all there is.
                let record = WorkoutRecord(startedAt: item.start, endedAt: item.end,
                                           activity: item.activity, source: .garmin)
                record.externalID = "garmin:\(item.id)"
                record.activeEnergyKcal = item.activeEnergyKcal ?? 0
                record.distanceMetres = item.distanceMetres
                record.avgHeartRate = item.avgHeartRate
                record.maxHeartRate = item.maxHeartRate
                record.elevationGainMetres = item.elevationGainMetres
                record.avgCadence = item.avgCadence
                record.avgPowerWatts = item.avgPowerWatts
                record.notes = item.trainingEffectSummary
                context.insert(record)
                added += 1
                continue
            }
            match.avgPowerWatts = match.avgPowerWatts ?? item.avgPowerWatts
            match.avgCadence = match.avgCadence ?? item.avgCadence
            match.maxHeartRate = match.maxHeartRate ?? item.maxHeartRate
            match.elevationGainMetres = match.elevationGainMetres ?? item.elevationGainMetres
            match.notes = item.trainingEffectSummary ?? match.notes
            if match.sourceName == nil { match.sourceName = "Garmin" }
        }
        return added
    }

    private func fetchRecords(in range: DateInterval) -> [WorkoutRecord] {
        let start = range.start
        let end = range.end
        return (try? context.fetch(FetchDescriptor<WorkoutRecord>(predicate: #Predicate {
            $0.startedAt >= start && $0.startedAt <= end
        }))) ?? []
    }

}
