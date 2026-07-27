import Foundation

/// Assembles engine input. A day's intake auto-completes at midnight: past days
/// count toward the TDEE estimate, today never does (still being logged).
/// Guard against the partial-day bias found in validation: a past day only
/// counts if ≥ `minPlausibleIntake` kcal was logged — below that it was almost
/// certainly an abandoned logging day, and including it would drag TDEE low.
/// Weight always counts.
enum MetabolicRecordAssembler {
    static let minPlausibleIntake = 800.0

    /// `supplementKcal` carries calorie-bearing supplements — protein powder,
    /// mass gainer, fish oil. Three shakes a day is ~340 kcal; leaving it out
    /// would inflate measured TDEE by exactly that much.
    static func dailyRecords(logs: [NutritionLog], metrics: [BodyMetrics],
                             supplementKcal: [Date: Double] = [:],
                             asOf: Date = .now) -> [DailyRecord] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: asOf)

        var intakeByDay: [Date: Double] = [:]
        for log in logs {
            let d = cal.startOfDay(for: log.date)
            guard d < today else { continue }
            intakeByDay[d, default: 0] += log.kcal
        }
        // Only added to days that already have food logged: a day whose sole
        // record is a standing creatine entry was not a logged day, and treating
        // it as one would drag the intake average toward zero.
        for (day, kcal) in supplementKcal where intakeByDay[day] != nil {
            intakeByDay[day, default: 0] += kcal
        }
        intakeByDay = intakeByDay.filter { $0.value >= minPlausibleIntake }

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
