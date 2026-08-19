import Foundation

/// One session's top working weight for an exercise — a point on its progress chart.
struct LiftProgressPoint: Sendable, Equatable, Identifiable {
    let date: Date
    let maxWeightKg: Double
    var id: Date { date }
}

/// An exercise's max-weight-per-session history, ascending by date.
struct LiftProgressSeries: Sendable, Identifiable {
    let exerciseID: UUID
    let points: [LiftProgressPoint]
    var id: UUID { exerciseID }
    var latest: LiftProgressPoint? { points.last }
    var earliest: LiftProgressPoint? { points.first }
}

/// Builds per-exercise strength-progress series from flat `LiftRecord`s.
enum LiftProgress {

    /// For each exercise, the **heaviest working set of each session** within
    /// `[start, now]`, as one point per session.
    ///
    /// A `LiftRecord`'s date is its session's start, so records sharing a date
    /// share a session — grouping by date is grouping by session, and two
    /// sessions on the same day stay distinct.
    ///
    /// Warm-ups and unweighted sets (0 kg) are excluded: the chart tracks the top
    /// working weight, and a warm-up or a bodyweight 0 would drag the line to the
    /// floor and hide the trend it exists to show. An exercise with no qualifying
    /// set in the window yields no series rather than an empty chart.
    static func series(records: [LiftRecord], since start: Date) -> [LiftProgressSeries] {
        var byExercise: [UUID: [Date: Double]] = [:]
        for r in records where !r.isWarmup && r.weightKg > 0 && r.date >= start {
            let previous = byExercise[r.exerciseID]?[r.date] ?? 0
            byExercise[r.exerciseID, default: [:]][r.date] = max(previous, r.weightKg)
        }
        return byExercise
            .map { id, byDate in
                let points = byDate
                    .map { LiftProgressPoint(date: $0.key, maxWeightKg: $0.value) }
                    .sorted { $0.date < $1.date }
                return LiftProgressSeries(exerciseID: id, points: points)
            }
            // Most recently trained first, so the page reads active lifts down to
            // dormant ones.
            .sorted { ($0.latest?.date ?? .distantPast) > ($1.latest?.date ?? .distantPast) }
    }

    /// `series`, then thinned by age so a six-month chart doesn't crowd — dense
    /// where recent progress matters, sparse where only the trend does:
    ///
    /// - **first month**: two points a week (the best set of each half-week),
    /// - **months 2–3**: one a week (the best set of the week),
    /// - **months 4–6**: one a fortnight (the best set of the fortnight).
    ///
    /// Every bucket keeps its heaviest session — a PR is never averaged away — and
    /// the point keeps that session's real date, so the x-position stays honest.
    /// How the per-session points are thinned for display.
    enum Sampling: Sendable {
        /// Age-tiered: dense recent, sparse old — for the fixed 1/3/6-month windows.
        case aged
        /// One point per calendar month (the month's best set) — for the all-time
        /// view, where the shape over years is the point and per-week detail would
        /// be an unreadable smear.
        case monthly
    }

    static func downsampledSeries(records: [LiftRecord], since start: Date,
                                  sampling: Sampling = .aged,
                                  asOf: Date = .now,
                                  calendar: Calendar = .current) -> [LiftProgressSeries] {
        series(records: records, since: start)
            .map { s in
                let points: [LiftProgressPoint]
                switch sampling {
                case .aged: points = downsample(s.points, asOf: asOf, calendar: calendar)
                case .monthly: points = monthlyDownsample(s.points, calendar: calendar)
                }
                return LiftProgressSeries(exerciseID: s.exerciseID, points: points)
            }
            .sorted { ($0.latest?.date ?? .distantPast) > ($1.latest?.date ?? .distantPast) }
    }

    /// The heaviest session of each calendar month, ascending by date, keeping the
    /// best session's real date.
    static func monthlyDownsample(_ points: [LiftProgressPoint],
                                  calendar: Calendar) -> [LiftProgressPoint] {
        var best: [Int: LiftProgressPoint] = [:]
        for point in points {
            let parts = calendar.dateComponents([.year, .month], from: point.date)
            let key = (parts.year ?? 0) * 12 + (parts.month ?? 0)
            if let existing = best[key], existing.maxWeightKg >= point.maxWeightKg { continue }
            best[key] = point
        }
        return best.values.sorted { $0.date < $1.date }
    }

    /// The best point of each age bucket, ascending by date.
    static func downsample(_ points: [LiftProgressPoint], asOf: Date,
                           calendar: Calendar) -> [LiftProgressPoint] {
        let today = calendar.startOfDay(for: asOf)
        var best: [Int: LiftProgressPoint] = [:]
        for point in points {
            let age = calendar.dateComponents([.day],
                                              from: calendar.startOfDay(for: point.date),
                                              to: today).day ?? 0
            let key = bucketKey(ageDays: max(age, 0))
            if let existing = best[key], existing.maxWeightKg >= point.maxWeightKg { continue }
            best[key] = point
        }
        return best.values.sorted { $0.date < $1.date }
    }

    /// A bucket id per age, namespaced by tier so buckets never straddle a
    /// boundary. First month in half-week (3.5-day) slots, then weekly, then
    /// fortnightly.
    static func bucketKey(ageDays age: Int) -> Int {
        switch age {
        case ..<30: return Int(Double(age) / 3.5)   // 0…8, ~two a week
        case ..<90: return 100 + (age - 30) / 7     // one a week
        default:    return 200 + (age - 90) / 14    // one a fortnight
        }
    }
}
