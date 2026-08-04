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

/// Weekly volume per muscle group.
///
/// Direct work and assisting work are counted separately and combined with very
/// different weights, because they are not interchangeable stimulus. See
/// `EffectiveVolume` and `assistingCeiling` for the reasoning.
struct VolumeAggregator: Sendable {

    /// Tension at or above which a set counts as a whole set *for display*.
    ///
    /// The weighted figure is the honest one and everything downstream keeps
    /// using it. But "0.8 sets" is not a thing anyone does in a gym: you either
    /// worked a muscle in that set or you didn't.
    ///
    /// Four, not three. A 3 is real involvement but not the reason you picked
    /// the exercise — the triceps in a bench press, the lower back in a squat.
    /// Counting those as whole sets inflates every number on the screen and
    /// makes it impossible to see which muscles were actually the target.
    static let fullSetTension = 4

    /// Whole sets per muscle, for display.
    ///
    /// A count of qualifying sets, deliberately not the weighted total rounded.
    /// Two sets at a 3 are two sets — rounding their 1.2 weighted total would
    /// report one, and would keep reporting one however many the user did until
    /// the fractions happened to cross a boundary.
    func weeklySetCounts(records: [LiftRecord],
                         muscles: [UUID: [MuscleGroup: Int]],
                         week: DateInterval) -> [MuscleGroup: Int] {
        var out: [MuscleGroup: Int] = [:]
        for r in records where !r.isWarmup && r.date >= week.start && r.date < week.end {
            guard let tension = muscles[r.exerciseID] else { continue }
            for (muscle, score) in tension where score >= Self.fullSetTension {
                out[muscle, default: 0] += 1
            }
        }
        return out
    }

    /// Sets that involved a muscle without targeting it — tension below
    /// `fullSetTension`.
    ///
    /// The counterpart to `weeklySetCounts`, and the reason it exists: raising
    /// the bar to 4 left the lower back in a squat and the forearms in a
    /// deadlift reading as a bare dash, on the same screen as a diagram that
    /// colours them. Five sets of squats is 2.0 weighted sets of lower back —
    /// real work, done, and worth naming rather than rounding to nothing.
    ///
    /// Counted separately rather than folded in: a set that assists is not a set
    /// that targets, and adding them would put back exactly the inflation
    /// `fullSetTension` was raised to remove.
    func weeklySecondarySetCounts(records: [LiftRecord],
                                  muscles: [UUID: [MuscleGroup: Int]],
                                  week: DateInterval) -> [MuscleGroup: Int] {
        var out: [MuscleGroup: Int] = [:]
        for r in records where !r.isWarmup && r.date >= week.start && r.date < week.end {
            guard let tension = muscles[r.exerciseID] else { continue }
            for (muscle, score) in tension where score > 0 && score < Self.fullSetTension {
                out[muscle, default: 0] += 1
            }
        }
        return out
    }

    /// What a week of training actually did to one muscle.
    ///
    /// Direct and assisting work are kept apart because they are not
    /// interchangeable, which is the flaw in counting `tension/5` sets and adding
    /// them up. Under that model ten sets of rows gave the biceps six sets —
    /// the same as six sets of curls — and a hard pull day alone could paint a
    /// muscle as maximally trained. It is not the same stimulus: in a row the
    /// biceps is not the limiting factor and is nowhere near failure when the
    /// set ends.
    struct EffectiveVolume: Sendable, Equatable {
        /// Sets where this muscle was the point of the exercise.
        let direct: Int
        /// Sets where it assisted.
        let secondary: Int
        /// Direct sets plus a discounted, capped credit for the assisting work.
        let effective: Double

        var hasDirect: Bool { direct > 0 }
        /// Worked, but never as the target — the biceps after a pull day.
        var isSecondaryOnly: Bool { direct == 0 && secondary > 0 }
    }

    /// What one *direct* set is worth.
    ///
    /// A 5 is the prime mover taken near failure; a 4 is a muscle genuinely
    /// targeted but sharing the work or the range. Both count as a whole set to
    /// the person doing them, which is why both show in the count — but they are
    /// not identical stimulus, and flattening them to 1.0 apiece would leave the
    /// table unable to order the chest above the front delts on a bench press.
    static func directCredit(tension: Int) -> Double {
        tension >= 5 ? 1.0 : 0.85
    }

    /// What one assisting set is worth, as a fraction of a direct set.
    ///
    /// Not `score/5`. A 3 is a muscle doing real work under moderate tension at
    /// a length and effort the exercise never pushes to failure; calling that
    /// 0.6 of a hard set overstates it roughly twofold. These are deliberately
    /// steep — assisting work is worth having and is not worth much.
    static func assistingCredit(tension: Int) -> Double {
        switch tension {
        case 3:  return 0.50
        case 2:  return 0.22
        case 1:  return 0.08
        default: return 0
        }
    }

    /// Assisting work with diminishing returns, approaching `ceiling`.
    ///
    ///     credit = ceiling × (1 − e^(−raw / ceiling))
    ///
    /// A hard cap was the first attempt and it was too blunt: it made the fifth
    /// assisting set worth full value and the sixth worth nothing. This is
    /// smooth — early assisting sets count for nearly their face value, later
    /// ones taper — which matches how the stimulus actually behaves, and means
    /// the answer never depends on where exactly a cliff was placed.
    ///
    /// It never reaches `ceiling`, so assistance alone can carry a muscle to a
    /// productive week and never past one.
    static func saturated(_ raw: Double, ceiling: Double) -> Double {
        guard ceiling > 0, raw > 0 else { return 0 }
        return ceiling * (1 - exp(-raw / ceiling))
    }

    /// Assisting work is capped per muscle — see `WeeklySetTargets.assistingCeiling`.
    ///
    /// The cap is the part that fixes the original complaint. Assistance
    /// saturates: the twentieth set of rows does almost nothing further for the
    /// biceps that the first five did not, because the stimulus is limited by
    /// how hard that muscle is being driven, not by how many times. Without a
    /// ceiling the model just re-derives "enough indirect work equals any amount
    /// of direct work", which is the thing that was wrong.

    /// Per-muscle volume within `week`.
    func weeklyVolume(records: [LiftRecord],
                      muscles: [UUID: [MuscleGroup: Int]],
                      week: DateInterval) -> [MuscleGroup: EffectiveVolume] {
        var direct: [MuscleGroup: Int] = [:]
        var secondary: [MuscleGroup: Int] = [:]
        var directCredit: [MuscleGroup: Double] = [:]
        var assistCredit: [MuscleGroup: Double] = [:]

        // Half-open, not `week.contains`: DateInterval.contains includes `end`,
        // and a week's end is the next week's start, so a set logged at midnight
        // on a Monday counted towards both weeks.
        for r in records where !r.isWarmup && r.date >= week.start && r.date < week.end {
            guard let tension = muscles[r.exerciseID] else { continue }
            for (muscle, score) in tension where score > 0 {
                if score >= Self.fullSetTension {
                    direct[muscle, default: 0] += 1
                    directCredit[muscle, default: 0] += Self.directCredit(tension: score)
                } else {
                    secondary[muscle, default: 0] += 1
                    assistCredit[muscle, default: 0] += Self.assistingCredit(tension: score)
                }
            }
        }

        var out: [MuscleGroup: EffectiveVolume] = [:]
        for muscle in Set(direct.keys).union(secondary.keys) {
            let d = direct[muscle] ?? 0
            let s = secondary[muscle] ?? 0
            let earned = directCredit[muscle] ?? 0
            let assisted = Self.saturated(assistCredit[muscle] ?? 0,
                                          ceiling: muscle.weeklyTargets.assistingCeiling)
            out[muscle] = EffectiveVolume(direct: d, secondary: s,
                                          effective: earned + assisted)
        }
        return out
    }

    /// Effective sets per muscle, for callers that only need the number.
    func weeklySets(records: [LiftRecord],
                    muscles: [UUID: [MuscleGroup: Int]],
                    week: DateInterval) -> [MuscleGroup: Double] {
        weeklyVolume(records: records, muscles: muscles, week: week)
            .mapValues(\.effective)
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
