import Foundation
import SwiftData

/// Pure EWMA fill shared by the aggregator and the weight chart.
enum TrendFill {
    static func ewma(_ values: [Double], n: Double = 10) -> [Double] {
        let alpha = 2 / (n + 1)
        var trend: Double?
        return values.map { v in
            trend = trend.map { alpha * v + (1 - alpha) * $0 } ?? v
            return trend!
        }
    }

    /// Time-aware EWMA: the smoothing weight decays with the *elapsed days*
    /// between readings, not their position in the array. Index-based smoothing
    /// treats a reading three months after the last one as the next step, so a
    /// stale trend leaks into a fresh measurement and the chart shows a slow
    /// drift the user never lived through.
    ///
    /// `dates` must be sorted ascending and the same length as `values`.
    static func ewma(_ values: [Double], dates: [Date], n: Double = 10) -> [Double] {
        guard values.count == dates.count else { return ewma(values, n: n) }
        let alpha = 2 / (n + 1)
        var trend: Double?
        var previous: Date?
        return zip(values, dates).map { value, date in
            defer { previous = date }
            guard let last = trend, let prior = previous else {
                trend = value
                return value
            }
            let gapDays = max(1, date.timeIntervalSince(prior) / 86_400)
            // Compounding one day's decay over the gap; a long gap drives the
            // effective alpha to 1, i.e. start fresh from this reading.
            let effectiveAlpha = 1 - pow(1 - alpha, gapDays)
            trend = effectiveAlpha * value + (1 - effectiveAlpha) * last
            return trend!
        }
    }
}

/// Recomputes all derived state: weight trend, metabolic estimates, today's
/// recovery score. Idempotent; run after every sync and on foreground.
@MainActor
final class AggregationService {
    private let context: ModelContext
    private let cal = Calendar(identifier: .gregorian)

    init(context: ModelContext) {
        self.context = context
    }

    func runAll(refreshWeightTrend: Bool = true) {
        if refreshWeightTrend { fillWeightTrend() }
        upsertMetabolicEstimates()
        refreshCyclicalPatterns()
        upsertTodayRecovery()
        upsertTodayStrain()
        try? context.save()
    }

    /// One-time repair for stores written before weight-derived values were kept
    /// consistently in sync. It replaces the unconditional launch rebuild: once
    /// repaired, ordinary launches only touch the trend when sync inserted a new
    /// weight or the user edited one.
    @discardableResult
    func repairWeightTrendIfNeeded(defaults: UserDefaults = .standard) -> Bool {
        let key = "superfit.weight-trend-repair-v2"
        guard !defaults.bool(forKey: key) else { return false }
        // The stored estimate is downstream of the trend and must be repaired
        // in the same pass; otherwise the chart changes while the target stays
        // stale until Health access returns.
        refreshWeightDerived()
        defaults.set(true, forKey: key)
        return true
    }

    /// Everything downstream of a change to the weight series.
    ///
    /// The smoothed trend alone is not enough: the calorie and macro targets are
    /// read from a stored `MetabolicEstimateRecord`, so rebuilding the trend and
    /// stopping there leaves the corrected weight showing in the list while the
    /// dashboard keeps quoting a target derived from the old one.
    ///
    /// Deliberately not `runAll` — recovery and the cyclical baselines are driven
    /// by sleep and HRV, and a weigh-in cannot move them.
    func refreshWeightDerived() {
        fillWeightTrend()
        upsertMetabolicEstimates()
        try? context.save()
    }

    // MARK: - Weight trend

    /// Smoothed over one value per day — the lowest — rather than over every
    /// reading. See `DailyWeight`.
    ///
    /// Feeding raw readings in was its own bug, separate from the choice of
    /// rule. Two weigh-ins on one day entered the EWMA as two successive points,
    /// and `TrendFill`'s time-aware decay floors the gap at one day, so a second
    /// weigh-in aged the trend a full day *and* dragged it toward the heavier
    /// number. Stepping on the scale twice moved the trend; the body hadn't.
    ///
    /// Every row of a day is then given that day's trend, so `basisWeightKg`
    /// answers the same thing whichever of the day's rows a caller reaches for.
    func fillWeightTrend() {
        let metrics = (try? context.fetch(FetchDescriptor<BodyMetrics>())) ?? []
        let byDay = DailyWeight.byDay(metrics, date: \.date,
                                      weightKg: \.weightKg, calendar: cal)
        let days = byDay.keys.sorted()
        let smoothed = TrendFill.ewma(days.compactMap { byDay[$0] }, dates: days)

        var trendByDay: [Date: Double] = [:]
        for (day, trend) in zip(days, smoothed) { trendByDay[day] = trend }
        for m in metrics {
            let value = trendByDay[cal.startOfDay(for: m.date)]
            if m.trendWeightKg != value { m.trendWeightKg = value }
        }
    }

    // MARK: - Metabolic estimates

    func upsertMetabolicEstimates() {
        guard let profile = (try? context.fetch(FetchDescriptor<UserProfile>()))?.first else { return }
        let now = Date.now
        let start = cal.date(byAdding: .day, value: -31, to: now) ?? now
        let logsQuery = FetchDescriptor<NutritionLog>(
            predicate: #Predicate { $0.date >= start && $0.date <= now })
        let logs = (try? context.fetch(logsQuery)) ?? []
        let metricsQuery = FetchDescriptor<BodyMetrics>(
            predicate: #Predicate { $0.date >= start && $0.date <= now },
            sortBy: [SortDescriptor(\.date)])
        var metrics = (try? context.fetch(metricsQuery)) ?? []
        // A user who weighs infrequently still needs the latest known weight for
        // the BMR prior even when it predates the 30-day measurement window.
        if metrics.isEmpty {
            var latest = FetchDescriptor<BodyMetrics>(sortBy: [SortDescriptor(\.date, order: .reverse)])
            latest.fetchLimit = 1
            metrics = (try? context.fetch(latest)) ?? []
        }
        guard !metrics.isEmpty else { return }

        let supplements = (try? context.fetch(FetchDescriptor<Supplement>())) ?? []
        let entries = (try? context.fetch(FetchDescriptor<SupplementEntry>())) ?? []
        let supplementKcal = SupplementIntake.dailyKcal(
            entries: entries, supplements: supplements,
            from: start, to: now)

        let records = MetabolicRecordAssembler.dailyRecords(
            logs: logs, metrics: metrics, supplementKcal: supplementKcal)
        let energyQuery = FetchDescriptor<DailyEnergy>(
            predicate: #Predicate { $0.date >= start && $0.date <= now })
        let energy = (try? context.fetch(energyQuery)) ?? []
        let prior = MetabolismEngine.Prior(
            sex: profile.sex, ageYears: profile.ageYears,
            heightCm: profile.heightCm, activity: profile.activity,
            avgActiveEnergyKcal: MetabolicRecordAssembler.avgActiveEnergy(energy: energy),
            leanMassKg: BodyComposition.recentLeanMassKg(metrics))
        let today = cal.startOfDay(for: now)
        let bounds = DayBounds(today, calendar: cal)
        let dayEnd = bounds.end
        let existingQuery = FetchDescriptor<MetabolicEstimateRecord>(
            predicate: #Predicate { $0.date >= today && $0.date < dayEnd })
        let existing = (try? context.fetch(existingQuery)) ?? []

        for window in [7, 14, 30] {
            let est = MetabolismEngine().estimate(records: records, windowDays: window, prior: prior)
            let row = existing.first { bounds.contains($0.date) && $0.windowDays == window }
                ?? {
                    let r = MetabolicEstimateRecord(date: today, window: window)
                    context.insert(r)
                    return r
                }()
            row.tdeeKcal = est.tdeeKcal
            row.confidence = est.confidence
            row.trendSlopeKgPerWeek = est.trendSlopeKgPerWeek
            row.avgIntakeKcal = est.avgIntakeKcal
            row.basalKcal = est.basalKcal
        }
    }

    // MARK: - Cyclical baselines

    /// Marker names, kept as constants so the persisted `markerRaw` can't drift.
    private enum Marker {
        static let hrv = "hrv"
        static let restingHR = "restingHR"
    }

    /// Looks for a recurring 21–35 day rhythm in HRV and resting HR, and records
    /// it when the evidence bar is met (≥3 complete cycles across ≥90 days).
    ///
    /// Detection runs regardless of profile — the maths doesn't care who you are,
    /// and running it for everyone keeps one code path. Whether the correction is
    /// *applied* is decided in `recoveryInputs`.
    func refreshCyclicalPatterns() {
        var originQuery = FetchDescriptor<DailyVitals>(
            sortBy: [SortDescriptor(\.date)])
        originQuery.fetchLimit = 1
        guard let origin = try? context.fetch(originQuery).first?.date else { return }
        let cutoff = Date.now.addingTimeInterval(-240 * 86_400)
        let windowQuery = FetchDescriptor<DailyVitals>(
            predicate: #Predicate { $0.date >= cutoff },
            sortBy: [SortDescriptor(\.date)])
        let window = (try? context.fetch(windowQuery)) ?? []

        func samples(_ value: (DailyVitals) -> Double?) -> [CyclicalSample] {
            window.compactMap { row in
                value(row).map {
                    CyclicalSample(day: Int(cal.startOfDay(for: row.date)
                        .timeIntervalSince(cal.startOfDay(for: origin)) / 86_400),
                                   value: $0)
                }
            }
        }

        store(CyclicalBaseline.detect(samples(\.hrvSDNN)), marker: Marker.hrv)
        store(CyclicalBaseline.detect(samples(\.restingHR)), marker: Marker.restingHR)
    }

    private func store(_ pattern: CyclicalPattern?, marker: String) {
        let matches = ((try? context.fetch(FetchDescriptor<CyclicalPatternRecord>())) ?? [])
            .filter { $0.markerRaw == marker }
            .sorted { $0.detectedAt > $1.detectedAt }
        let existing = matches.first
        for duplicate in matches.dropFirst() { context.delete(duplicate) }
        guard let pattern else {
            existing?.isActive = false     // kept, so a flickering pattern is visible
            return
        }
        let row = existing ?? {
            let r = CyclicalPatternRecord(marker: marker)
            context.insert(r)
            return r
        }()
        row.detectedAt = .now
        row.periodDays = pattern.periodDays
        row.cyclesObserved = pattern.cyclesObserved
        row.strength = pattern.strength
        row.amplitude = pattern.amplitude
        row.profile = pattern.profile
        row.isActive = true
    }

    /// Stored patterns that currently qualify and apply to this user. Both
    /// recovery markers are loaded together so one recovery pass does not fetch
    /// the same profile and tiny table twice.
    ///
    /// Gated on a female profile by product decision. The detector itself is
    /// blind — a 21–35 day rhythm could show up in anyone's data from shift work
    /// or training blocks — so restricting the correction avoids "fixing"
    /// baselines on a coincidence for the population where no such physiology is
    /// expected. `.other` is excluded because it carries no information either
    /// way, and silently reshaping someone's recovery scores on an assumption is
    /// worse than leaving them alone.
    private func activePatterns() -> [String: CyclicalPattern] {
        guard let profile = (try? context.fetch(FetchDescriptor<UserProfile>()))?.first,
              profile.sex == .female else { return [:] }
        let rows = ((try? context.fetch(FetchDescriptor<CyclicalPatternRecord>())) ?? [])
            .sorted { $0.detectedAt < $1.detectedAt }
        var patterns: [String: CyclicalPattern] = [:]
        for row in rows {
            guard row.isActive, row.profile.count == row.periodDays, row.periodDays > 0
            else { continue }
            // Newest valid row wins until the next refresh physically removes
            // duplicates left by a CloudKit merge.
            patterns[row.markerRaw] = CyclicalPattern(
                periodDays: row.periodDays,
                cyclesObserved: row.cyclesObserved,
                strength: row.strength,
                amplitude: row.amplitude,
                profile: row.profile)
        }
        return patterns
    }

    // MARK: - Recovery

    func upsertTodayRecovery() {
        let today = cal.startOfDay(for: .now)
        let result = RecoveryEngine().evaluate(recoveryInputs(for: today))

        let bounds = DayBounds(today, calendar: cal)
        let dayEnd = bounds.end
        let query = FetchDescriptor<RecoveryScoreRecord>(
            predicate: #Predicate { $0.date >= today && $0.date < dayEnd })
        let existing = (try? context.fetch(query)) ?? []
        let row = existing.first { bounds.contains($0.date) }
            ?? {
                let r = RecoveryScoreRecord(date: today, score: 0, recommendation: "")
                context.insert(r)
                return r
            }()
        row.score = result.score
        row.recommendationRaw = result.recommendation.rawValue
        row.dataCompleteness = result.dataCompleteness
    }

    // MARK: - Strain

    /// Today's total workout strain. Heart-rate sessions use minute TRIMP;
    /// unrated strength and phone-only sessions fall back through RPE and logged
    /// set effort, so a missing watch no longer erases work the user recorded.
    func upsertTodayStrain() {
        let today = cal.startOfDay(for: .now)
        guard let profile = (try? context.fetch(FetchDescriptor<UserProfile>()))?.first else { return }

        let vitals = (try? context.fetch(FetchDescriptor<DailyVitals>())) ?? []
        let restingHR = vitals.sorted { $0.date > $1.date }.compactMap(\.restingHR).first

        let windowStart = cal.date(byAdding: .day, value: -StrainEngine.referenceWindowDays,
                                   to: today) ?? today
        let workoutQuery = FetchDescriptor<WorkoutRecord>(
            predicate: #Predicate { $0.startedAt >= windowStart })
        let workoutRecords = (try? context.fetch(workoutQuery)) ?? []

        let sessionQuery = FetchDescriptor<TrainingSession>(
            predicate: #Predicate { $0.startedAt >= windowStart })
        let localSessions: [(interval: DateInterval, input: StrainWorkout)] =
            ((try? context.fetch(sessionQuery)) ?? []).compactMap { session in
            guard let endedAt = session.endedAt, endedAt > session.startedAt else { return nil }
            let sets = (session.sets ?? []).filter {
                $0.completedAt != nil && !$0.isWarmup && $0.reps > 0
            }.map { StrainStrengthSet(reps: $0.reps, rir: $0.rir) }
            let input = StrainWorkout(
                date: session.startedAt,
                durationMinutes: endedAt.timeIntervalSince(session.startedAt) / 60,
                sessionRPE: session.sessionRPE,
                strengthSets: sets)
            return (DateInterval(start: session.startedAt, end: endedAt), input)
        }

        let strengthRecordIndices = workoutRecords.indices.filter {
            workoutRecords[$0].activity.isStrength && workoutRecords[$0].durationSeconds > 0
        }
        let matches = WorkoutTimeMatcher.matches(
            workouts: strengthRecordIndices.map {
                DateInterval(start: workoutRecords[$0].startedAt,
                             end: workoutRecords[$0].endedAt)
            },
            sessions: localSessions.map(\.interval))
        let recordToSession = Dictionary(uniqueKeysWithValues: matches.map {
            (strengthRecordIndices[$0.key], $0.value)
        })
        let sessionToRecord = Dictionary(uniqueKeysWithValues: recordToSession.map {
            ($0.value, $0.key)
        })

        // Unmatched imports stand alone. A matched watch workout is represented
        // below by its richer phone session, carrying the watch's HR signal.
        var inputs: [StrainWorkout] = workoutRecords.enumerated().compactMap { pair in
            let (index, record) = pair
            guard recordToSession[index] == nil else { return nil }
            return StrainWorkout(date: record.startedAt,
                                 durationMinutes: record.durationSeconds / 60,
                                 avgHeartRate: record.avgHeartRate,
                                 heartRateSegments: record.heartRateSegments,
                                 sessionRPE: record.sessionRPE)
        }
        inputs += localSessions.enumerated().map { pair in
            let (index, local) = pair
            guard let recordIndex = sessionToRecord[index] else { return local.input }
            let watch = workoutRecords[recordIndex]
            let hasWatchHR = watch.avgHeartRate != nil || !watch.heartRateSegments.isEmpty
            return StrainWorkout(
                date: local.input.date,
                durationMinutes: hasWatchHR ? watch.durationSeconds / 60
                                            : local.input.durationMinutes,
                avgHeartRate: watch.avgHeartRate,
                heartRateSegments: watch.heartRateSegments,
                sessionRPE: local.input.sessionRPE ?? watch.sessionRPE,
                strengthSets: local.input.strengthSets)
        }

        let result = StrainEngine().evaluate(workouts: inputs, on: today,
                                             restingHR: restingHR,
                                             age: Double(profile.ageYears),
                                             isFemale: profile.sex == .female,
                                             calendar: cal)

        let bounds = DayBounds(today, calendar: cal)
        let dayEnd = bounds.end
        let query = FetchDescriptor<StrainRecord>(
            predicate: #Predicate { $0.date >= today && $0.date < dayEnd })
        let existing = (try? context.fetch(query)) ?? []
        let row = existing.first { bounds.contains($0.date) }
            ?? {
                let r = StrainRecord(date: today, strain: 0, rawTrimp: 0,
                                     bandRaw: "", dataCompleteness: 0)
                context.insert(r)
                return r
            }()
        row.strain = result?.strain ?? 0
        row.rawTrimp = result?.rawTrimp ?? 0
        row.bandRaw = result?.band.rawValue ?? ""
        row.dataCompleteness = result?.dataCompleteness ?? 0
    }

    func recoveryInputs(for day: Date) -> RecoveryInputs {
        var inputs = RecoveryInputs()

        let bounds = DayBounds(day, calendar: cal)
        let dayStart = bounds.start
        let dayEnd = bounds.end
        let sleepQuery = FetchDescriptor<SleepData>(
            predicate: #Predicate { $0.date >= dayStart && $0.date < dayEnd })
        if let last = try? context.fetch(sleepQuery).first {
            inputs.asleepMinutes = last.asleepMinutes
            inputs.sleepEfficiency = last.efficiency
        }

        let baselineStart = day.addingTimeInterval(-60 * 86_400)
        let vitalsQuery = FetchDescriptor<DailyVitals>(
            predicate: #Predicate { $0.date >= baselineStart && $0.date < dayEnd },
            sortBy: [SortDescriptor(\.date)])
        let vitals = (try? context.fetch(vitalsQuery)) ?? []
        let baseline = vitals.filter { $0.date < day }
        let todayVitals = vitals.first { bounds.contains($0.date) }

        // Level both sides by the same rhythm before comparing. Correcting only
        // today's reading would shift it against an uncorrected baseline and
        // invert the very error being fixed.
        var originQuery = FetchDescriptor<DailyVitals>(sortBy: [SortDescriptor(\.date)])
        originQuery.fetchLimit = 1
        let origin = (try? context.fetch(originQuery).first)
            .map { cal.startOfDay(for: $0.date) }
        func dayIndex(_ date: Date) -> Int {
            guard let origin else { return 0 }
            return Int(cal.startOfDay(for: date).timeIntervalSince(origin) / 86_400)
        }

        func levelled(_ values: [(Date, Double)], _ pattern: CyclicalPattern?) -> [Double] {
            guard let pattern else { return values.map(\.1) }
            return values.map { $0.1 - pattern.offset(forDay: dayIndex($0.0)) }
        }

        let patterns = activePatterns()
        let hrvPattern = patterns[Marker.hrv]
        let rhrPattern = patterns[Marker.restingHR]

        if let todayVitals {
            inputs.hrv = todayVitals.hrvSDNN.map {
                $0 - (hrvPattern?.offset(forDay: dayIndex(todayVitals.date)) ?? 0)
            }
            inputs.restingHR = todayVitals.restingHR.map {
                $0 - (rhrPattern?.offset(forDay: dayIndex(todayVitals.date)) ?? 0)
            }
        }

        let hrvs = levelled(baseline.compactMap { v in v.hrvSDNN.map { (v.date, $0) } }, hrvPattern)
        if hrvs.count >= 5 {
            inputs.hrvBaselineMean = mean(hrvs)
            inputs.hrvBaselineSD = sd(hrvs)
        }
        let rhrs = levelled(baseline.compactMap { v in v.restingHR.map { (v.date, $0) } }, rhrPattern)
        if rhrs.count >= 5 {
            inputs.rhrBaselineMean = mean(rhrs)
            inputs.rhrBaselineSD = sd(rhrs)
        }

        // Only the ACWR window is needed; fetching all history grows unbounded.
        let chronicStart = day.addingTimeInterval(-28 * 86_400)
        let sessionQuery = FetchDescriptor<TrainingSession>(
            predicate: #Predicate { $0.startedAt >= chronicStart })
        let sessions = (try? context.fetch(sessionQuery)) ?? []

        let fractions = Dictionary(
            ((try? context.fetch(FetchDescriptor<Exercise>())) ?? [])
                .map { ($0.id, $0.bodyweightFraction) },
            uniquingKeysWith: { a, _ in a })
        let records = TrainingRecords.completed(sessions, fractions: fractions)
        // Bodyweight makes unweighted work count toward load. Trend weight, not
        // the latest reading, so a water-weight spike can't move training load.
        var weightQuery = FetchDescriptor<BodyMetrics>(
            predicate: #Predicate { $0.date <= day },
            sortBy: [SortDescriptor(\.date, order: .reverse)])
        weightQuery.fetchLimit = 1
        let bodyweight = (try? context.fetch(weightQuery).first)
            .map { $0.trendWeightKg ?? $0.weightKg } ?? 0

        let agg = VolumeAggregator()
        let acuteWindow = DateInterval(start: day.addingTimeInterval(-7 * 86_400), end: day)
        let chronicWindow = DateInterval(start: chronicStart, end: day)
        let acute = agg.tonnage(records: records, in: acuteWindow, bodyweightKg: bodyweight)
        let chronicWeekly = agg.tonnage(records: records, in: chronicWindow,
                                        bodyweightKg: bodyweight) / 4
        if chronicWeekly > 0 {
            inputs.acuteLoad = acute
            inputs.chronicLoad = chronicWeekly
        }
        return inputs
    }

    private func mean(_ xs: [Double]) -> Double { xs.reduce(0, +) / Double(xs.count) }

    private func sd(_ xs: [Double]) -> Double {
        let m = mean(xs)
        return (xs.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(xs.count - 1)).squareRoot()
    }
}
