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

/// A distance-bearing workout reduced to what a distance trend needs — the
/// value-type input to `HistorySeries`, so the shaping stays free of SwiftData.
struct CardioDistanceRecord: Sendable {
    let date: Date
    let activity: WorkoutActivity
    let distanceMetres: Double
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
        metabolismEstimates(records: records, windowDays: windowDays,
                            from: start, to: end, calendar: calendar) { _ in prior }
            .compactMap { day, estimate in
            // Nothing to say until some intake has actually been logged.
            guard estimate.confidence > 0 else { return nil }
                // ±15% at zero confidence narrowing to ±3% at full — the residual
                // spread the DLW validation measured, widened by how much of the
                // number is still prior rather than measurement.
                let spread = estimate.tdeeKcal * (0.03 + 0.12 * (1 - estimate.confidence))
                return HistoryBand(date: day,
                                   value: estimate.tdeeKcal,
                                   lower: estimate.tdeeKcal - spread,
                                   upper: estimate.tdeeKcal + spread)
            }
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
        metabolismEstimates(records: records, windowDays: windowDays,
                            from: start, to: end, calendar: calendar) { _ in prior }
            .compactMap { day, estimate in
            // The slope needs weigh-ins, not intake, so it stands on its own.
                guard estimate.smoothedWeightKg > 0 else { return nil }
                return HistoryPoint(date: day, value: estimate.trendSlopeKgPerWeek)
            }
    }

    /// Estimates a date range in one pass. The old chart path filtered and
    /// sorted every stored record once per plotted day (365 full scans for the
    /// year view). Two moving indices keep the same inclusive window semantics
    /// while touching each record only as it enters or leaves the window.
    static func metabolismEstimates(
        records: [DailyRecord],
        windowDays: Int,
        from start: Date,
        to end: Date,
        calendar: Calendar = .current,
        prior: (Date) -> MetabolismEngine.Prior?
    ) -> [(date: Date, estimate: TDEEEstimate)] {
        let last = calendar.startOfDay(for: end)
        var day = calendar.startOfDay(for: start)
        var days: [Date] = []
        while day <= last {
            days.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return metabolismEstimates(records: records, windowDays: windowDays,
                                   on: days, calendar: calendar, prior: prior)
    }

    /// Sparse-date form used by adherence charts, which only need estimates on
    /// days that actually contain a food log.
    static func metabolismEstimates(
        records: [DailyRecord],
        windowDays: Int,
        on days: [Date],
        calendar: Calendar = .current,
        prior: (Date) -> MetabolismEngine.Prior?
    ) -> [(date: Date, estimate: TDEEEstimate)] {
        let sorted = records.sorted { $0.date < $1.date }
        let requestedDays = Set(days.map { calendar.startOfDay(for: $0) }).sorted()
        let engine = MetabolismEngine()
        let gregorian = Calendar(identifier: .gregorian)
        var lower = 0
        var upper = 0
        var out: [(Date, TDEEEstimate)] = []

        for day in requestedDays {
            let windowStart = gregorian.date(byAdding: .day, value: -windowDays,
                                             to: day) ?? day
            while lower < sorted.count, sorted[lower].date < windowStart { lower += 1 }
            if upper < lower { upper = lower }
            while upper < sorted.count, sorted[upper].date <= day { upper += 1 }

            if let dayPrior = prior(day) {
                let window = Array(sorted[lower..<upper])
                out.append((day, engine.estimatePrepared(
                    records: window, windowDays: windowDays,
                    prior: dayPrior, asOf: day)))
            }
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
        /// Carbs and fats are judged inside a band this wide either way.
        static let bandTolerance = 0.10

        /// Whether a day counts, which is not the same question for every macro.
        enum Rule: Sendable {
            /// More is fine, short is a miss. Protein: eating over target costs
            /// nothing, so only the shortfall matters.
            case floor
            /// Over is as much a miss as under. Carbs and fats are a budget
            /// inside a calorie target — doubling your fat is not adherence.
            case band
        }

        func hit(_ rule: Rule) -> Bool {
            switch rule {
            case .floor: return actual >= target * Self.tolerance
            case .band:  return abs(actual - target) <= target * Self.bandTolerance
            }
        }

        var hit: Bool { hit(.floor) }
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
    // MARK: Cardio

    /// Per-session distance (metres) for one activity within a range,
    /// chronological. Only sessions that actually recorded a distance count — a
    /// GPS-less run or a strength session reads as no data, never a zero, so the
    /// trend can't be dragged down by an unmeasured session.
    static func distanceTrend(_ records: [CardioDistanceRecord],
                              activity: WorkoutActivity,
                              from start: Date, to end: Date) -> [HistoryPoint] {
        records
            .filter { $0.activity == activity && $0.date >= start && $0.date <= end
                      && $0.distanceMetres > 0 }
            .sorted { $0.date < $1.date }
            .map { HistoryPoint(date: $0.date, value: $0.distanceMetres) }
    }

    /// Distance activities the user actually logged in the range, most-frequent
    /// first — the picker's options, so it never offers one with no data.
    static func loggedDistanceActivities(_ records: [CardioDistanceRecord],
                                         from start: Date, to end: Date) -> [WorkoutActivity] {
        var counts: [WorkoutActivity: Int] = [:]
        for record in records
        where record.date >= start && record.date <= end && record.distanceMetres > 0 {
            counts[record.activity, default: 0] += 1
        }
        return counts.sorted {
            $0.value != $1.value ? $0.value > $1.value : $0.key.rawValue < $1.key.rawValue
        }.map(\.key)
    }

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
