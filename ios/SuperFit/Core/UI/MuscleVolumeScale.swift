import SwiftUI

/// A week of training on one muscle, as a colour.
///
/// Purely the mapping. The numbers behind it — what counts as a direct set,
/// what assisting work is worth, and where the bands sit — belong to
/// `VolumeAggregator`, because they are a claim about training rather than
/// about presentation.
///
/// **What each colour means**
///
/// | Colour | Meaning |
/// |---|---|
/// | Grey | Not trained |
/// | Yellow | Trained, but only as a secondary muscle, or not enough sets |
/// | Green | Regular and recommended — enough to maintain or build slowly |
/// | Blue | A high weekly volume for an average gym-goer |
/// | Purple | Very high; challenging for most people to recover from |
///
/// A body that is green everywhere is the target: every muscle trained enough
/// to hold or slowly improve. Green is therefore *good*, not middling, and
/// purple is a warning as much as an achievement.
///
/// **Yellow carries two different meanings on purpose.** "Only ever assisted"
/// and "directly trained but not enough" are both answered by the same action —
/// give this muscle more direct sets — so they share a colour. The table beside
/// the diagram is what distinguishes them: it labels the first case *secondary*.
enum MuscleVolumeScale {

    static let untrained = Theme.homeWell
    static let insufficient = Color(red: 0.95, green: 0.77, blue: 0.20)   // yellow
    static let productive = Color(red: 0.35, green: 0.78, blue: 0.42)     // green
    static let high = Color(red: 0.30, green: 0.62, blue: 0.93)           // blue
    static let veryHigh = Color(red: 0.63, green: 0.44, blue: 0.90)       // purple

    /// The colour for a week's work on one muscle.
    ///
    /// **Assisting work alone can reach green, and never blue.** The colour is a
    /// comparison — how hard you trained this muscle against how hard most
    /// people do — so twenty sets of rows should not leave the biceps reading as
    /// neglected. They have been worked, genuinely. What they have not had is
    /// the kind of week that builds them fastest, which is why the saturation in
    /// `WeeklySetTargets.assistingCeiling` keeps assistance short of blue
    /// however much of it there is.
    static func colour(for volume: VolumeAggregator.EffectiveVolume?,
                       muscle: MuscleGroup) -> Color {
        guard let volume, volume.effective > 0 else { return untrained }
        let t = muscle.weeklyTargets
        switch volume.effective {
        case ..<t.productiveFrom: return insufficient
        case ..<t.highFrom:       return productive
        case ..<t.veryHighFrom:   return high
        default:                  return veryHigh
        }
    }

    /// Legend for one muscle size — the numbers differ between them, so a
    /// single legend would be wrong for two thirds of the body.
    static func legend(for size: MuscleSize) -> [(label: String, detail: String, colour: Color)] {
        let t = size.targets
        func n(_ v: Double) -> String { String(Int(v)) }
        return [
            ("Not trained", "nothing logged", untrained),
            ("Needs work", "secondary only, or under \(n(t.productiveFrom))", insufficient),
            ("On track", "\(n(t.productiveFrom)) to \(n(t.highFrom))", productive),
            ("High", "\(n(t.highFrom)) to \(n(t.veryHighFrom))", high),
            ("Very high", "\(n(t.veryHighFrom))+, competitive volume", veryHigh),
        ]
    }
}
