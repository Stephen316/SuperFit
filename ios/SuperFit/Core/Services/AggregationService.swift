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
        upsertTodayRecovery()
        try? context.save()
    }

    // MARK: - Weight trend

    func fillWeightTrend() {
        let metrics = ((try? context.fetch(FetchDescriptor<BodyMetrics>())) ?? [])
            .sorted { $0.date < $1.date }
        let smoothed = TrendFill.ewma(metrics.map(\.weightKg))
        for (m, t) in zip(metrics, smoothed) { m.trendWeightKg = t }
    }

    // MARK: - Metabolic estimates

    func upsertMetabolicEstimates() {
        guard let profile = (try? context.fetch(FetchDescriptor<UserProfile>()))?.first else { return }
        let logs = (try? context.fetch(FetchDescriptor<NutritionLog>())) ?? []
        let metrics = (try? context.fetch(FetchDescriptor<BodyMetrics>())) ?? []
        let statuses = (try? context.fetch(FetchDescriptor<DayLogStatus>())) ?? []
        guard !metrics.isEmpty else { return }

        let records = MetabolicRecordAssembler.dailyRecords(logs: logs, metrics: metrics, statuses: statuses)
        let energy = (try? context.fetch(FetchDescriptor<DailyEnergy>())) ?? []
        let prior = MetabolismEngine.Prior(
            sex: profile.sex, ageYears: profile.ageYears,
            heightCm: profile.heightCm, activity: profile.activity,
            avgActiveEnergyKcal: MetabolicRecordAssembler.avgActiveEnergy(energy: energy))
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
        }
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
        if let todayVitals = vitals.first(where: { cal.isDate($0.date, inSameDayAs: day) }) {
            inputs.hrv = todayVitals.hrvSDNN
            inputs.restingHR = todayVitals.restingHR
        }
        let hrvs = baseline.compactMap(\.hrvSDNN)
        if hrvs.count >= 5 {
            inputs.hrvBaselineMean = mean(hrvs)
            inputs.hrvBaselineSD = sd(hrvs)
        }
        let rhrs = baseline.compactMap(\.restingHR)
        if rhrs.count >= 5 {
            inputs.rhrBaselineMean = mean(rhrs)
            inputs.rhrBaselineSD = sd(rhrs)
        }

        let sessions = (try? context.fetch(FetchDescriptor<TrainingSession>())) ?? []
        let records = sessions.flatMap { s in
            (s.sets ?? []).compactMap { set -> LiftRecord? in
                guard let id = set.exerciseID else { return nil }
                return LiftRecord(date: s.startedAt, exerciseID: id,
                                  weightKg: set.weightKg, reps: set.reps, isWarmup: set.isWarmup)
            }
        }
        let agg = VolumeAggregator()
        let acuteWindow = DateInterval(start: day.addingTimeInterval(-7 * 86_400), end: day)
        let chronicWindow = DateInterval(start: day.addingTimeInterval(-28 * 86_400), end: day)
        let acute = agg.tonnage(records: records, in: acuteWindow)
        let chronicWeekly = agg.tonnage(records: records, in: chronicWindow) / 4
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
