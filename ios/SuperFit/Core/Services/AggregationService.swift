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

    func runAll() {
        fillWeightTrend()
        upsertMetabolicEstimates()
        refreshCyclicalPatterns()
        upsertTodayRecovery()
        try? context.save()
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
        for m in metrics { m.trendWeightKg = trendByDay[cal.startOfDay(for: m.date)] }
    }

    // MARK: - Metabolic estimates

    func upsertMetabolicEstimates() {
        guard let profile = (try? context.fetch(FetchDescriptor<UserProfile>()))?.first else { return }
        let logs = (try? context.fetch(FetchDescriptor<NutritionLog>())) ?? []
        let metrics = (try? context.fetch(FetchDescriptor<BodyMetrics>())) ?? []
        guard !metrics.isEmpty else { return }

        let supplements = (try? context.fetch(FetchDescriptor<Supplement>())) ?? []
        let entries = (try? context.fetch(FetchDescriptor<SupplementEntry>())) ?? []
        let earliest = metrics.map(\.date).min() ?? .now
        let supplementKcal = SupplementIntake.dailyKcal(
            entries: entries, supplements: supplements,
            from: max(earliest, Date.now.addingTimeInterval(-120 * 86_400)), to: .now)

        let records = MetabolicRecordAssembler.dailyRecords(
            logs: logs, metrics: metrics, supplementKcal: supplementKcal)
        let energy = (try? context.fetch(FetchDescriptor<DailyEnergy>())) ?? []
        let prior = MetabolismEngine.Prior(
            sex: profile.sex, ageYears: profile.ageYears,
            heightCm: profile.heightCm, activity: profile.activity,
            avgActiveEnergyKcal: MetabolicRecordAssembler.avgActiveEnergy(energy: energy),
            leanMassKg: BodyComposition.recentLeanMassKg(metrics))
        let today = cal.startOfDay(for: .now)
        let existing = (try? context.fetch(FetchDescriptor<MetabolicEstimateRecord>())) ?? []

        for window in [7, 14, 30] {
            let est = MetabolismEngine().estimate(records: records, windowDays: window, prior: prior)
            let row = existing.first { cal.isDate($0.date, inSameDayAs: today) && $0.windowDays == window }
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
        let vitals = ((try? context.fetch(FetchDescriptor<DailyVitals>())) ?? [])
            .sorted { $0.date < $1.date }
        guard let origin = vitals.first?.date else { return }
        let cutoff = Date.now.addingTimeInterval(-240 * 86_400)
        let window = vitals.filter { $0.date >= cutoff }

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
        let existing = ((try? context.fetch(FetchDescriptor<CyclicalPatternRecord>())) ?? [])
            .first { $0.markerRaw == marker }
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

    /// The stored pattern for a marker, if it currently qualifies *and* applies
    /// to this user.
    ///
    /// Gated on a female profile by product decision. The detector itself is
    /// blind — a 21–35 day rhythm could show up in anyone's data from shift work
    /// or training blocks — so restricting the correction avoids "fixing"
    /// baselines on a coincidence for the population where no such physiology is
    /// expected. `.other` is excluded because it carries no information either
    /// way, and silently reshaping someone's recovery scores on an assumption is
    /// worse than leaving them alone.
    private func activePattern(_ marker: String) -> CyclicalPattern? {
        guard let profile = (try? context.fetch(FetchDescriptor<UserProfile>()))?.first,
              profile.sex == .female,
              let row = ((try? context.fetch(FetchDescriptor<CyclicalPatternRecord>())) ?? [])
                  .first(where: { $0.markerRaw == marker && $0.isActive }),
              row.profile.count == row.periodDays, row.periodDays > 0
        else { return nil }
        return CyclicalPattern(periodDays: row.periodDays,
                               cyclesObserved: row.cyclesObserved,
                               strength: row.strength,
                               amplitude: row.amplitude,
                               profile: row.profile)
    }

    // MARK: - Recovery

    func upsertTodayRecovery() {
        let today = cal.startOfDay(for: .now)
        let result = RecoveryEngine().evaluate(recoveryInputs(for: today))

        let existing = (try? context.fetch(FetchDescriptor<RecoveryScoreRecord>())) ?? []
        let row = existing.first { cal.isDate($0.date, inSameDayAs: today) }
            ?? {
                let r = RecoveryScoreRecord(date: today, score: 0, recommendation: "")
                context.insert(r)
                return r
            }()
        row.score = result.score
        row.recommendationRaw = result.recommendation.rawValue
        row.dataCompleteness = result.dataCompleteness
    }

    func recoveryInputs(for day: Date) -> RecoveryInputs {
        var inputs = RecoveryInputs()

        let sleep = (try? context.fetch(FetchDescriptor<SleepData>())) ?? []
        if let last = sleep.first(where: { cal.isDate($0.date, inSameDayAs: day) }) {
            inputs.asleepMinutes = last.asleepMinutes
            inputs.sleepEfficiency = last.efficiency
        }

        let vitals = ((try? context.fetch(FetchDescriptor<DailyVitals>())) ?? [])
            .sorted { $0.date < $1.date }
        let baselineStart = day.addingTimeInterval(-60 * 86_400)
        let baseline = vitals.filter { $0.date >= baselineStart && $0.date < day }
        let todayVitals = vitals.first { cal.isDate($0.date, inSameDayAs: day) }

        // Level both sides by the same rhythm before comparing. Correcting only
        // today's reading would shift it against an uncorrected baseline and
        // invert the very error being fixed.
        let origin = vitals.first.map { cal.startOfDay(for: $0.date) }
        func dayIndex(_ date: Date) -> Int {
            guard let origin else { return 0 }
            return Int(cal.startOfDay(for: date).timeIntervalSince(origin) / 86_400)
        }

        func levelled(_ values: [(Date, Double)], _ pattern: CyclicalPattern?) -> [Double] {
            guard let pattern else { return values.map(\.1) }
            return values.map { $0.1 - pattern.offset(forDay: dayIndex($0.0)) }
        }

        let hrvPattern = activePattern(Marker.hrv)
        let rhrPattern = activePattern(Marker.restingHR)

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
        let bodyweight = ((try? context.fetch(FetchDescriptor<BodyMetrics>())) ?? [])
            .sorted { $0.date > $1.date }
            .first
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
