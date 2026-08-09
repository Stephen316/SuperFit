import Foundation

/// Sleep efficiency banded for display — time asleep as a fraction of time in bed.
///
/// **85% is the clinical threshold** for healthy adult sleep; below it, sleep is
/// fragmented even when the hours look adequate, and it tends to track disrupted
/// nights before duration does.
///
/// Banded on the **rounded percentage**, so the word agrees with the number on the
/// gauge — the same rule recovery and strain follow.
enum SleepEfficiencyBand: String, Sendable, CaseIterable {
    case poor = "Poor"
    case fair = "Fair"
    case good = "Good"
    case excellent = "Excellent"

    init(roundedPercent percent: Double) {
        switch percent {
        case ..<75: self = .poor
        case ..<85: self = .fair
        case ..<90: self = .good
        default: self = .excellent
        }
    }
}
