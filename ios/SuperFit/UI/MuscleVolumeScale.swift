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

    /// Where a week's work on one muscle lands.
    ///
    /// An ordered type rather than a bare colour, because the bands need to be
    /// averaged across the body for the summary — and colours cannot be.
    enum Band: Int, CaseIterable, Comparable {
        case untrained = 0, needsWork, onTrack, high, veryHigh

        var colour: Color {
            switch self {
            case .untrained: return MuscleVolumeScale.untrained
            case .needsWork: return MuscleVolumeScale.insufficient
            case .onTrack:   return MuscleVolumeScale.productive
            case .high:      return MuscleVolumeScale.high
            case .veryHigh:  return MuscleVolumeScale.veryHigh
            }
        }

        var title: String {
            switch self {
            case .untrained: return "Not trained"
            case .needsWork: return "Needs work"
            case .onTrack:   return "On track"
            case .high:      return "High"
            case .veryHigh:  return "Very high"
            }
        }

        static func < (a: Band, b: Band) -> Bool { a.rawValue < b.rawValue }
    }

    /// The band a week's work on one muscle falls in.
    ///
    /// **Assisting work alone can reach green, and never blue.** The colour is a
    /// comparison — how hard you trained this muscle against how hard most
    /// people do — so twenty sets of rows should not leave the biceps reading as
    /// neglected. They have been worked, genuinely. What they have not had is
    /// the kind of week that builds them fastest, which is why the saturation in
    /// `WeeklySetTargets.assistingCeiling` keeps assistance short of blue
    /// however much of it there is.
    static func band(for volume: VolumeAggregator.EffectiveVolume?,
                     muscle: MuscleGroup) -> Band {
        guard let volume, volume.effective > 0 else { return .untrained }
        let t = muscle.weeklyTargets
        switch volume.effective {
        case ..<t.productiveFrom: return .needsWork
        case ..<t.highFrom:       return .onTrack
        case ..<t.veryHighFrom:   return .high
        default:                  return .veryHigh
        }
    }

    static func colour(for volume: VolumeAggregator.EffectiveVolume?,
                       muscle: MuscleGroup) -> Color {
        band(for: volume, muscle: muscle).colour
    }

    /// The whole body's week, as one band.
    ///
    /// The mean band across every muscle group, rounded to the nearest. Averaged
    /// on the *band* rather than on sets, because raw sets are not comparable
    /// between a quad and a wrist flexor — each muscle is already judged against
    /// its own targets by the time it has a band, so the bands are the only
    /// figures on a common scale.
    ///
    /// Every group counts, including ones never touched. A summary that quietly
    /// ignored the muscles you skipped would say you were on track in the exact
    /// case where you are not.
    static func overall(_ volumes: [MuscleGroup: VolumeAggregator.EffectiveVolume]) -> Band {
        let all = MuscleGroup.allCases
        guard !all.isEmpty else { return .untrained }
        let total = all.reduce(0) { $0 + band(for: volumes[$1], muscle: $1).rawValue }
        let mean = Double(total) / Double(all.count)
        return Band(rawValue: Int(mean.rounded())) ?? .untrained
    }
}
