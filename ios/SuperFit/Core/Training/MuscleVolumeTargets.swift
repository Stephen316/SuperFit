import Foundation

/// How much weekly volume a muscle wants, by how big it is.
///
/// A single global threshold was wrong in both directions: it asked as much of
/// the biceps as of the quads, so arms looked under-trained on a normal week and
/// legs looked finished on half of one. Recovery capacity and productive volume
/// both scale with muscle size, so the bands do too.
enum MuscleSize: Sendable {
    case large      // back, legs
    case medium     // chest, shoulders, calves
    case small      // arms, core
    case tiny       // muscles almost nobody trains directly

    /// Weekly effective sets at which each band begins.
    ///
    /// **Purple begins where competitive practice begins.** Reported IFBB-level
    /// weekly volumes are 16–22 sets for large groups, 12–18 for medium and
    /// 10–16 for small. The *bottom* of each of those ranges is where purple
    /// starts here, so purple means "you are training at the volume people who
    /// do this for a living train at" — which is exactly the warning it should
    /// be for someone with a job and a life.
    ///
    /// Green and blue are then spaced beneath: green from roughly 45% of the
    /// professional floor, blue from roughly 70%. Green is the range to live in,
    /// blue is a hard block on one muscle, purple is not somewhere to be for
    /// long — and never for every muscle at once.
    var targets: WeeklySetTargets {
        switch self {
        //                                        green      blue      purple
        case .large:  return WeeklySetTargets(productiveFrom: 7, highFrom: 11, veryHighFrom: 16)
        case .medium: return WeeklySetTargets(productiveFrom: 5, highFrom: 8,  veryHighFrom: 12)
        case .small:  return WeeklySetTargets(productiveFrom: 4, highFrom: 7,  veryHighFrom: 10)
        // Serratus, sartorius, tibialis anterior and friends. Nobody programmes
        // four direct sets of these, so judging them on the arm scale left them
        // permanently yellow — a row that never changes is not information. The
        // numbers are low because the honest question for these muscles is
        // "did anything work it at all", not "did you hit your volume target".
        case .tiny:   return WeeklySetTargets(productiveFrom: 2, highFrom: 4,  veryHighFrom: 6)
        }
    }
}

struct WeeklySetTargets: Sendable, Equatable {
    /// Green from here — regular, recommended, enough to build slowly.
    let productiveFrom: Double
    /// Blue from here — a high week, around what a competitor does.
    let highFrom: Double
    /// Purple from here — past most people's recoverable ceiling.
    let veryHighFrom: Double

    /// The band a target line should aim at.
    var recommended: ClosedRange<Double> { productiveFrom...highFrom }

    /// What assisting work asymptotically approaches, however much you do.
    ///
    /// Set at the top of green, so the rule reads: **no amount of assisting work
    /// alone makes a muscle high-volume, but plenty of it is a real week\'s
    /// work.** Twenty sets of rows have genuinely trained your biceps harder
    /// than most people train theirs, and the colour is a statement about that
    /// comparison — it just never becomes the same thing as training them.
    ///
    /// The approach is asymptotic rather than a hard cap: credit never quite
    /// reaches this, so a muscle can never be pushed out of green by assistance.
    var assistingCeiling: Double { highFrom }
}

extension MuscleGroup {

    /// Which volume class this muscle belongs to.
    ///
    /// Classified by the muscle itself rather than by the split it is usually
    /// trained on. The heads matter less than they look: a set of close-grip
    /// bench drives all three triceps heads at once, so per-head weekly volume
    /// lands close to the whole-group figure the published ranges describe.
    var size: MuscleSize {
        switch self {
        // Back and legs — the big movers, trained heavy and recovered slowly.
        case .lats, .erectorSpinae,
             .gluteusMaximus,
             .vastusLateralis, .vastusMedialis, .rectusFemoris,
             .bicepsFemoris, .semitendinosus,
             .adductorMagnus:
            return .large

        // Chest and shoulders, plus the mid-size scapular and calf muscles.
        case .chest, .upperChest,
             .frontDelts, .sideDelts, .rearDelts,
             .upperTraps, .middleTraps, .lowerTraps, .rhomboids,
             .gluteusMedius,
             .gastrocnemius, .soleus,
             .adductorLongus:
            return .medium

        // Arms and core — small, but trained directly by anyone who cares about
        // them, so they are judged on whether you actually did.
        case .biceps,
             .tricepsLong, .tricepsLateral, .tricepsMedial,
             .brachioradialis, .wristFlexors, .wristExtensors,
             .upperAbs, .lowerAbs, .obliques:
            return .small

        // Worked almost entirely as assistance. Held to a much lower bar
        // because "four direct sets of sartorius" is not a thing anyone does.
        case .serratus, .pectineus, .sartorius, .tibialisAnterior, .peroneals:
            return .tiny
        }
    }

    /// Shorthand for the bands this muscle is judged against.
    var weeklyTargets: WeeklySetTargets { size.targets }
}
