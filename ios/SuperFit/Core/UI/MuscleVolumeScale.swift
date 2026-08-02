import SwiftUI

/// Weekly volume to a colour on the body diagram.
///
/// Read off the *weighted* set total, not the whole-set count beside it in the
/// table: three sets of bench are three sets for both chest and front delts, and
/// painting them the same shade would throw away the only thing the diagram is
/// there to show.
///
/// The bounds are the ones asked for. They are lower than the hypertrophy
/// literature's productive range — the usual figure is nearer 10–20 hard sets
/// per muscle per week, with 4–6 closer to a maintenance dose — so a muscle
/// showing purple here has had a solid week rather than a maximal one. That is a
/// deliberate choice about what the scale is *for*: flagging neglect at a glance
/// beats grading effort, and a scale topping out at 20 leaves nearly every
/// muscle grey for nearly everyone. Raising the bounds later is a change to this
/// one table.
enum MuscleVolumeScale {

    /// Upper bound of each band, in weighted sets. Open-ended above the last.
    static let bands: [(upTo: Double, colour: Color)] = [
        (3,  Color(red: 0.95, green: 0.77, blue: 0.20)),   // 1–2  yellow
        (5,  Color(red: 0.35, green: 0.78, blue: 0.42)),   // 3–4  green
        (6,  Color(red: 0.30, green: 0.62, blue: 0.93)),   // 5    blue
    ]

    static let sixPlus = Color(red: 0.63, green: 0.44, blue: 0.90)   // 6+  purple

    /// Below this the muscle reads as untrained.
    ///
    /// Not zero. A weighted total this low is a muscle that was carried through
    /// somebody else's exercise — a squat's share of lower back, a press's
    /// share of triceps — and colouring that the same as a muscle you actually
    /// trained makes the diagram claim work that never happened.
    ///
    /// Just under a full set rather than a full one, so that a single hard set
    /// registers: one set at tension 4 is 0.8 weighted, and a muscle you gave a
    /// real set to should not read as untouched.
    static let minimumTrained = 0.8

    /// Nothing logged, or not enough to count. An untouched muscle has to be
    /// findable at a glance, which is the whole point of the scale.
    static let untrained = Theme.homeWell

    static func colour(forWeightedSets sets: Double) -> Color {
        guard sets > minimumTrained else { return untrained }
        for band in bands where sets < band.upTo { return band.colour }
        return sixPlus
    }

    /// Legend order, for anywhere that needs to explain the scale.
    static let legend: [(label: String, colour: Color)] = [
        ("Barely worked", untrained),
        ("1–2 sets", bands[0].colour),
        ("3–4", bands[1].colour),
        ("5", bands[2].colour),
        ("6+", sixPlus),
    ]
}
