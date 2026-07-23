import Foundation

/// Assembles engine input, honoring the day-complete flag: intake only counts on
/// days the user marked fully logged (prevents partial-day bias — see
/// docs/ALGORITHMS.md); weight always counts.
enum MetabolicRecordAssembler {
    static func dailyRecords(logs: [NutritionLog], metrics: [BodyMetrics],
                             statuses: [DayLogStatus]) -> [DailyRecord] {
        let cal = Calendar.current
        let completeDays = Set(statuses.filter(\.loggingComplete)
            .map { cal.startOfDay(for: $0.date) })

        var intakeByDay: [Date: Double] = [:]
        for log in logs {
            let d = cal.startOfDay(for: log.date)
            guard completeDays.contains(d) else { continue }
            intakeByDay[d, default: 0] += log.kcal
        }
        var weightByDay: [Date: Double] = [:]
        for m in metrics { weightByDay[cal.startOfDay(for: m.date)] = m.weightKg }

        return Set(intakeByDay.keys).union(weightByDay.keys).sorted().map {
            DailyRecord(date: $0, intakeKcal: intakeByDay[$0], weightKg: weightByDay[$0])
        }
    }

    /// Mean daily active energy over the last `days`. Requires ≥7 days of data —
    /// below that a couple of unusual days would skew the prior.
    static func avgActiveEnergy(energy: [DailyEnergy], days: Int = 30,
                                asOf: Date = .now) -> Double? {
        let start = asOf.addingTimeInterval(-Double(days) * 86_400)
        let window = energy.filter { $0.date >= start && $0.activeEnergyKcal > 0 }
        guard window.count >= 7 else { return nil }
        return window.reduce(0) { $0 + $1.activeEnergyKcal } / Double(window.count)
    }
}
