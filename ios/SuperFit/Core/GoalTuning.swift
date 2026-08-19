import Foundation

/// How the chosen goal tunes training and what it nudges the user toward — the
/// goal-specific behaviour of #27 (strength) and #28 (every goal).
///
/// Kept out of `MetabolismEngine` (which owns the *nutrition* side of a goal:
/// calorie offset and protein) so training concerns stay separate, and pure so
/// the values are testable off-device.
extension FitnessGoal {
    /// Reps a fresh set starts at under this goal. Strength trains heavy and
    /// low; the others use the general default. Study-backed: maximal-strength
    /// work lives at ~1–5 reps, hypertrophy/recomposition at ~6–12.
    ///
    /// Rest follows from this rather than a separate knob: the set-based
    /// `defaultRest` gives a ≤3-rep set ~4 minutes, so a strength lifter's
    /// low-rep sets get the long rest without a second setting to keep in sync.
    var repTarget: Int {
        switch self {
        case .strength: return 3
        default: return 8
        }
    }
}

/// A short, deterministic (not AI) nudge for the current goal — surfaced in the
/// profile so each goal points the user at what it most depends on (#28).
enum GoalGuidance {
    static func tip(for goal: FitnessGoal) -> String {
        switch goal {
        case .fatLoss:
            return "Fat loss leans on daily movement. Add a cardio session or hit your steps on rest days to widen the deficit without cutting food further."
        case .recomposition:
            return "Recomposition is slow by design: hold protein high and train each muscle hard — the scale barely moves while your composition shifts."
        case .maintenance:
            return "Maintaining: keep intake near your measured expenditure and train to hold what you've built."
        case .muscleGain:
            return "Muscle gain needs a small surplus and enough weekly sets per muscle — chase the volume targets on the muscle map."
        case .strength:
            return "Strength is heavy and low-rep: prioritise the big lifts, rest 3–5 minutes between top sets, and add load before reps."
        }
    }
}
