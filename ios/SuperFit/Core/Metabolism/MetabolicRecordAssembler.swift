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
}
