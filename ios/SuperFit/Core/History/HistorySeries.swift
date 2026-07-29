import Foundation

/// One dated value, the shape every chart consumes.
struct HistoryPoint: Sendable, Identifiable {
    let date: Date
    let value: Double
    var id: Date { date }
}

/// A dated value with a band around it, for series that carry uncertainty.
struct HistoryBand: Sendable, Identifiable {
    let date: Date
    let value: Double
    let lower: Double
    let upper: Double
    var id: Date { date }
}

/// Turns stored records into chartable series.
///
/// Pure and Sendable — no SwiftData, no I/O — so the shaping is testable without
/// a store, same as the engines.
struct HistorySeries: Sendable {

    // MARK: Energy

    /// TDEE recomputed as of each day rather than read from stored records.
    ///
    /// `MetabolicEstimateRecord` only gains a row on days the app was opened, so
    /// reading it back gives a chart full of holes that say more about phone
    /// habits than metabolism. `MetabolismEngine.estimate` takes `asOf:`, so the
    /// whole history can be recomputed from the logs — and the result is what the
    /// app *would* have told you on each of those days.
    ///
    /// The band is the confidence-implied uncertainty: low confidence means the
    /// prior is carrying the estimate, and the chart should show that rather than
    /// drawing a thin line through a guess.
    static func tdee(records: [DailyRecord],
                     prior: MetabolismEngine.Prior,
                     windowDays: Int = 30,
                     from start: Date,
                     to end: Date,
                     calendar: Calendar = .current) -> [HistoryBand] {
        let engine = MetabolismEngine()
        var out: [HistoryBand] = []
        var day = calendar.startOfDay(for: start)
        let last = calendar.startOfDay(for: end)

        while day <= last {
            let estimate = engine.estimate(records: records, windowDays: windowDays,
                                           prior: prior, asOf: day)
            // Nothing to say until some intake has actually been logged.
            if estimate.confidence > 0 {
                // ±15% at zero confidence narrowing to ±3% at full — the residual
                // spread the DLW validation measured, widened by how much of the
                // number is still prior rather than measurement.
                let spread = estimate.tdeeKcal * (0.03 + 0.12 * (1 - estimate.confidence))
                out.append(HistoryBand(date: day,
                                       value: estimate.tdeeKcal,
                                       lower: estimate.tdeeKcal - spread,
                                       upper: estimate.tdeeKcal + spread))
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return out
    }

    /// Daily calories in, from food and supplements.
    static func intake(records: [DailyRecord]) -> [HistoryPoint] {
        records.compactMap { record in
            record.intakeKcal.map { HistoryPoint(date: record.date, value: $0) }
        }
        .sorted { $0.date < $1.date }
    }

    /// Intake minus expenditure per day — negative is a deficit.
    ///
    /// The number the whole app is really about, and the one a user otherwise
    /// has to compute by eyeballing two lines. Only produced for days that have
    /// both a logged intake and an estimate, so a blank day reads as absent
    /// rather than as a 2,500 kcal deficit.
    static func energyBalance(intake: [HistoryPoint],
                              tdee: [HistoryBand],
                              calendar: Calendar = .current) -> [HistoryPoint] {
        let expenditure = Dictionary(
            tdee.map { (calendar.startOfDay(for: $0.date), $0.value) },
            uniquingKeysWith: { a, _ in a })
        return intake.compactMap { point in
            expenditure[calendar.startOfDay(for: point.date)].map {
                HistoryPoint(date: point.date, value: point.value - $0)
            }
        }
    }

    /// Weight-change rate in kg/week, recomputed as of each day.
    ///
    /// The current rate is already shown as a figure; this is how it has moved.
    /// A rate that steepens past the guardrail is the early warning that a cut
    /// has tipped from fat loss into lean-mass loss, and a single number can't
    /// show that turning.
    ///
    /// A shorter window than TDEE uses — 14 days — because the point is to catch
    /// the rate *changing*, and a 30-day slope smooths away the very turn being
    /// looked for.
    static func rateOfChange(records: [DailyRecord],
                             prior: MetabolismEngine.Prior,
                             windowDays: Int = 14,
                             from start: Date,
                             to end: Date,
                             calendar: Calendar = .current) -> [HistoryPoint] {
        let engine = MetabolismEngine()
        var out: [HistoryPoint] = []
        var day = calendar.startOfDay(for: start)
        let last = calendar.startOfDay(for: end)

        while day <= last {
            let estimate = engine.estimate(records: records, windowDays: windowDays,
                                           prior: prior, asOf: day)
            // The slope needs weigh-ins, not intake, so it stands on its own.
            if estimate.smoothedWeightKg > 0 {
                out.append(HistoryPoint(date: day, value: estimate.trendSlopeKgPerWeek))
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return out
    }

    /// The safe weekly-change band for a bodyweight, as kg/week.
    /// Mirrors the guardrails in `MetabolismEngine.calorieTarget` so the chart
    /// and the target can't disagree about what "too fast" means.
    static func rateGuardrails(bodyweightKg: Double) -> (loss: Double, gain: Double) {
        (loss: -bodyweightKg * 0.01, gain: bodyweightKg * 0.005)
    }

    // MARK: Adherence

    struct AdherencePoint: Sendable, Identifiable {
        let date: Date
        let actual: Double
        let target: Double
        var id: Date { date }
        /// Tolerance for rounding and portion estimation, not for missing.
        /// 95% of a 150 g target is 142.5 g — a near miss counts, a 15 g
        /// shortfall doesn't, so "days on target" stays a number worth trusting.
        static let tolerance = 0.95
        var hit: Bool { actual >= target * Self.tolerance }
    }

    /// Daily protein against that day's target.
    ///
    /// The target is recomputed per day rather than held fixed: it tracks
    /// bodyweight and the calorie target, both of which move over a cut, so a
    /// fixed line would misreport adherence at both ends of the period.
    static func proteinAdherence(dailyProtein: [Date: Double],
                                 dailyTarget: [Date: Double],
                                 calendar: Calendar = .current) -> [AdherencePoint] {
        dailyProtein.compactMap { day, actual in
            dailyTarget[calendar.startOfDay(for: day)].map {
                AdherencePoint(date: day, actual: actual, target: $0)
            }
        }
        .sorted { $0.date < $1.date }
    }

    /// Share of days that reached target within tolerance.
    static func hitRate(_ points: [AdherencePoint]) -> Double? {
        guard !points.isEmpty else { return nil }
        return Double(points.filter(\.hit).count) / Double(points.count)
    }

    // MARK: Generic shaping

    /// Daily series from any dated values, keeping the last reading per day.
    static func daily<T>(_ items: [T],
                         date: (T) -> Date,
                         value: (T) -> Double?,
                         calendar: Calendar = .current) -> [HistoryPoint] {
        var byDay: [Date: (Date, Double)] = [:]
        for item in items {
            guard let v = value(item) else { continue }
            let d = date(item)
            let key = calendar.startOfDay(for: d)
            if let existing = byDay[key], existing.0 > d { continue }
            byDay[key] = (d, v)
        }
        return byDay.map { HistoryPoint(date: $0.key, value: $0.value.1) }
            .sorted { $0.date < $1.date }
    }

    /// Trailing mean, for laying a readable line over noisy daily points.
    /// Returns nothing until a full window exists rather than showing a partial
    /// average that looks like a trend.
    static func rollingMean(_ points: [HistoryPoint], window: Int = 7) -> [HistoryPoint] {
        guard points.count >= window else { return [] }
        let sorted = points.sorted { $0.date < $1.date }
        return (window - 1..<sorted.count).map { i in
            let slice = sorted[(i - window + 1)...i]
            let mean = slice.reduce(0) { $0 + $1.value } / Double(window)
            return HistoryPoint(date: sorted[i].date, value: mean)
        }
    }

    // MARK: Training

    /// Weekly working-set volume for one muscle, ISO weeks.
    static func weeklySets(records: [LiftRecord],
                           muscles: [UUID: [MuscleGroup: Int]],
                           muscle: MuscleGroup,
                           from start: Date,
                           to end: Date) -> [HistoryPoint] {
        var calendar = Calendar(identifier: .iso8601)
        calendar.firstWeekday = 2
        let aggregator = VolumeAggregator()
        var out: [HistoryPoint] = []
        // Start on the week boundary and step by each week's own end. Walking
        // +7d from an unaligned `start` visits weeks offset from the calendar's,
        // which drops the trailing days of the range: a Sunday-start 14-day
        // window lost 6 of its 14 days. Only a Monday start was ever correct.
        var cursor = calendar.dateInterval(of: .weekOfYear, for: start)?.start ?? start

        while cursor <= end {
            guard let week = calendar.dateInterval(of: .weekOfYear, for: cursor) else { break }
            let sets = aggregator.weeklySets(records: records, muscles: muscles, week: week)
            out.append(HistoryPoint(date: week.start, value: sets[muscle] ?? 0))
            cursor = week.end
        }
        return out
    }

    /// Best estimated 1RM per week for one exercise — the strength trend that a
    /// single current-vs-previous comparison can't show.
    static func e1RMHistory(records: [LiftRecord],
                            exerciseID: UUID,
                            from start: Date,
                            to end: Date) -> [HistoryPoint] {
        var calendar = Calendar(identifier: .iso8601)
        calendar.firstWeekday = 2
        let analyzer = ProgressionAnalyzer()

        var bestByWeek: [Date: Double] = [:]
        for record in records
        where record.exerciseID == exerciseID && !record.isWarmup
            && record.date >= start && record.date <= end {
            guard let week = calendar.dateInterval(of: .weekOfYear, for: record.date) else { continue }
            let value = analyzer.e1RM(weightKg: record.weightKg, reps: record.reps)
            bestByWeek[week.start] = max(bestByWeek[week.start] ?? 0, value)
        }
        return bestByWeek.map { HistoryPoint(date: $0.key, value: $0.value) }
            .sorted { $0.date < $1.date }
    }

    // MARK: Summary

    /// Change across a series, for the "down 2.4 kg" line above a chart.
    /// Uses the mean of the first and last week rather than single endpoints,
    /// which would let one noisy day define the whole period.
    static func change(_ points: [HistoryPoint], edgeDays: Int = 7) -> Double? {
        let sorted = points.sorted { $0.date < $1.date }
        guard sorted.count >= 2 else { return nil }
        let n = min(edgeDays, sorted.count / 2)
        guard n >= 1 else { return nil }
        let first = sorted.prefix(n).reduce(0) { $0 + $1.value } / Double(n)
        let last = sorted.suffix(n).reduce(0) { $0 + $1.value } / Double(n)
        return last - first
    }
}
