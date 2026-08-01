import Foundation

/// Value snapshot of one working set — pure input for the analyzers, decoupled
/// from SwiftData so they stay testable and portable.
struct LiftRecord: Sendable {
    let date: Date
    let exerciseID: UUID
    /// External load only. Zero for unweighted bodyweight work — the body's own
    /// contribution comes from `bodyweightFraction`.
    let weightKg: Double
    let reps: Int
    let isWarmup: Bool
    /// Share of bodyweight moved by this exercise (0 for machine/barbell work,
    /// 1.0 for a pull-up, ~0.65 for a push-up). Without it a calisthenics
    /// session scores zero training load and the recovery engine reads the
    /// athlete as fully rested.
    var bodyweightFraction: Double = 0

    /// Load actually moved per rep.
    func effectiveLoadKg(bodyweightKg: Double) -> Double {
        weightKg + bodyweightFraction * bodyweightKg
    }
}

/// Weekly working-set volume per muscle group, weighted by tension score:
/// a set contributes score/5 sets to each muscle (5 = full set, 2 = 0.4 sets).
/// Finer-grained than the classic primary=1/secondary=0.5 accounting.
struct VolumeAggregator: Sendable {

    static let weeklySetTargets: ClosedRange<Double> = 10...20

    /// Sets per muscle group within `week`, tension-weighted.
    func weeklySets(records: [LiftRecord],
                    muscles: [UUID: [MuscleGroup: Int]],
                    week: DateInterval) -> [MuscleGroup: Double] {
        var out: [MuscleGroup: Double] = [:]
        // Half-open, not `week.contains`: DateInterval.contains includes `end`,
        // and a week's end is the next week's start, so a set logged at midnight
        // on a Monday counted towards both weeks.
        for r in records where !r.isWarmup && r.date >= week.start && r.date < week.end {
            guard let tension = muscles[r.exerciseID] else { continue }
            for (muscle, score) in tension {
                out[muscle, default: 0] += Double(score) / 5
            }
        }
        return out
    }

    /// Total tonnage (kg lifted) in an interval — the training-load input for
    /// the recovery engine's ACWR. `bodyweightKg` lets unweighted work count;
    /// pass the user's current weight.
    func tonnage(records: [LiftRecord], in interval: DateInterval,
                 bodyweightKg: Double = 0) -> Double {
        records.filter { !$0.isWarmup && interval.contains($0.date) }
            .reduce(0) { $0 + $1.effectiveLoadKg(bodyweightKg: bodyweightKg) * Double($1.reps) }
    }

    /// Distinct training days in an interval.
    func frequency(records: [LiftRecord], in interval: DateInterval) -> Int {
        let cal = Calendar(identifier: .gregorian)
        return Set(records.filter { interval.contains($0.date) }
            .map { cal.startOfDay(for: $0.date) }).count
    }
}

struct ExerciseProgression: Sendable {
    let exerciseID: UUID
    let currentE1RM: Double
    let previousE1RM: Double
    /// Fractional change, e.g. 0.05 = +5%.
    var change: Double { previousE1RM > 0 ? (currentE1RM - previousE1RM) / previousE1RM : 0 }
}

/// Strength progression via estimated 1RM trend (Epley), best-set per half-window.
struct ProgressionAnalyzer: Sendable {

    /// Epley e1RM; reps capped at 12 — the formula degrades badly beyond that.
    /// A single counts as its own 1RM: Epley at r=1 overpredicts by 3.3%
    /// (benchmark vs NSCA %1RM table caught this).
    func e1RM(weightKg: Double, reps: Int) -> Double {
        guard reps > 0, weightKg > 0 else { return 0 }
        guard reps > 1 else { return weightKg }
        return weightKg * (1 + Double(min(reps, 12)) / 30)
    }

    /// Best e1RM in the recent half of `window` vs the earlier half, per exercise.
    /// Exercises trained in only one half are omitted (no comparison possible).
    func progressions(records: [LiftRecord], window: DateInterval) -> [ExerciseProgression] {
        let mid = window.start.addingTimeInterval(window.duration / 2)
        var earlier: [UUID: Double] = [:]
        var recent: [UUID: Double] = [:]
        for r in records where !r.isWarmup && window.contains(r.date) {
            let value = e1RM(weightKg: r.weightKg, reps: r.reps)
            if r.date < mid {
                earlier[r.exerciseID] = max(earlier[r.exerciseID] ?? 0, value)
            } else {
                recent[r.exerciseID] = max(recent[r.exerciseID] ?? 0, value)
            }
        }
        return recent.compactMap { id, current in
            guard let previous = earlier[id] else { return nil }
            return ExerciseProgression(exerciseID: id, currentE1RM: current, previousE1RM: previous)
        }
        .sorted { $0.change > $1.change }
    }
}
