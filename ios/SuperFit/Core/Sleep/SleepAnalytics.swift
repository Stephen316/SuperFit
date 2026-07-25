import Foundation

struct SleepNight: Sendable {
    let date: Date
    let asleepMinutes: Int
    let inBedMinutes: Int
    let deepMinutes: Int
    let remMinutes: Int
    let coreMinutes: Int
    let bedtime: Date?
    let wakeTime: Date?

    var efficiency: Double? {
        inBedMinutes > 0 ? Double(asleepMinutes) / Double(inBedMinutes) : nil
    }
    var hasStages: Bool { deepMinutes + remMinutes + coreMinutes > 0 }
}

struct SleepSummary: Sendable {
    let averageAsleepMinutes: Double
    let averageEfficiency: Double?   // nil when no night recorded time in bed
    let debtMinutes: Double            // cumulative shortfall vs need, 0 if none
    let consistencySD: Double?         // SD of bedtime in minutes; nil if unknown
    let nights: Int
}

/// Correlation between sleep duration and next-morning recovery markers.
struct SleepImpact: Sendable {
    let longNightHRV: Double
    let shortNightHRV: Double
    let thresholdMinutes: Int
    let longNights: Int
    let shortNights: Int

    /// Percent difference in HRV on well-slept mornings.
    var hrvDeltaPercent: Double {
        shortNightHRV == 0 ? 0 : (longNightHRV - shortNightHRV) / shortNightHRV * 100
    }
}

struct SleepAnalytics: Sendable {

    static let defaultNeedMinutes = 480

    func summary(_ nights: [SleepNight], needMinutes: Int = defaultNeedMinutes) -> SleepSummary? {
        let slept = nights.filter { $0.asleepMinutes > 0 }
        guard !slept.isEmpty else { return nil }

        let avgAsleep = Double(slept.reduce(0) { $0 + $1.asleepMinutes }) / Double(slept.count)
        let efficiencies = slept.compactMap(\.efficiency)
        let avgEff = efficiencies.isEmpty ? nil
            : efficiencies.reduce(0, +) / Double(efficiencies.count)
        let debt = slept.reduce(0.0) { $0 + max(0, Double(needMinutes - $1.asleepMinutes)) }

        return SleepSummary(averageAsleepMinutes: avgAsleep,
                            averageEfficiency: avgEff,
                            debtMinutes: debt,
                            consistencySD: bedtimeConsistency(slept),
                            nights: slept.count)
    }

    /// SD of bedtime, in minutes. Bedtimes are mapped onto a continuous axis
    /// centred on midnight so 23:50 and 00:10 read as 20 minutes apart rather
    /// than 23 hours.
    func bedtimeConsistency(_ nights: [SleepNight]) -> Double? {
        let cal = Calendar.current
        let offsets: [Double] = nights.compactMap { night in
            guard let bedtime = night.bedtime else { return nil }
            let c = cal.dateComponents([.hour, .minute], from: bedtime)
            guard let h = c.hour, let m = c.minute else { return nil }
            let minutes = Double(h * 60 + m)
            return h >= 12 ? minutes - 1440 : minutes   // evening → negative
        }
        guard offsets.count >= 3 else { return nil }
        let mean = offsets.reduce(0, +) / Double(offsets.count)
        let variance = offsets.reduce(0.0) { $0 + pow($1 - mean, 2) } / Double(offsets.count)
        return variance.squareRoot()
    }

    /// Splits nights at `thresholdMinutes` and compares mean HRV on the
    /// following morning. Needs ≥4 nights either side to report anything —
    /// below that a single outlier dominates.
    func impact(nights: [SleepNight], hrvByDay: [Date: Double],
                thresholdMinutes: Int = 450) -> SleepImpact? {
        let cal = Calendar.current
        var long: [Double] = []
        var short: [Double] = []
        for night in nights where night.asleepMinutes > 0 {
            guard let hrv = hrvByDay[cal.startOfDay(for: night.date)] else { continue }
            if night.asleepMinutes >= thresholdMinutes { long.append(hrv) } else { short.append(hrv) }
        }
        guard long.count >= 4, short.count >= 4 else { return nil }
        return SleepImpact(longNightHRV: long.reduce(0, +) / Double(long.count),
                           shortNightHRV: short.reduce(0, +) / Double(short.count),
                           thresholdMinutes: thresholdMinutes,
                           longNights: long.count,
                           shortNights: short.count)
    }

    /// Trailing mean over `window` nights, aligned to the input order.
    func rollingAverage(_ nights: [SleepNight], window: Int = 7) -> [(date: Date, minutes: Double)] {
        let sorted = nights.filter { $0.asleepMinutes > 0 }.sorted { $0.date < $1.date }
        guard sorted.count >= window else { return [] }
        return (window - 1..<sorted.count).map { i in
            let slice = sorted[(i - window + 1)...i]
            let mean = Double(slice.reduce(0) { $0 + $1.asleepMinutes }) / Double(window)
            return (sorted[i].date, mean)
        }
    }
}
