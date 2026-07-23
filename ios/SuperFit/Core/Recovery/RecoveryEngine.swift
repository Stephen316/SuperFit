import Foundation

enum TrainingRecommendation: String, Sendable {
    case pushIntensity   = "Push intensity"
    case normalTraining  = "Normal training"
    case reduceVolume    = "Reduce volume"
    case recoveryFocus   = "Recovery focus"
}

struct RecoveryResult: Sendable {
    let score: Double            // 0…100
    let recommendation: TrainingRecommendation
    let sleepScore: Double?
    let hrvScore: Double?
    let rhrScore: Double?
    let loadScore: Double?
    let dataCompleteness: Double // fraction of components present
}

/// Today's recovery inputs plus the user's own rolling baselines.
struct RecoveryInputs: Sendable {
    var asleepMinutes: Int?
    var sleepEfficiency: Double?      // 0…1
    var hrv: Double?                  // ms SDNN
    var restingHR: Double?            // bpm
    var acuteLoad: Double?            // last 7-day training volume
    var chronicLoad: Double?          // 28-day avg of 7-day volume

    var hrvBaselineMean: Double?
    var hrvBaselineSD: Double?
    var rhrBaselineMean: Double?
    var rhrBaselineSD: Double?

    var sleepNeedMinutes: Int = 480   // 8 h
}

/// Oura/Bevel-style readiness. Scores each metric against the user's own baseline;
/// missing components drop out and remaining weights renormalize.
/// See docs/ALGORITHMS.md §3.
struct RecoveryEngine: Sendable {

    private static let weights: [String: Double] =
        ["sleep": 0.35, "hrv": 0.30, "rhr": 0.20, "load": 0.15]

    func evaluate(_ i: RecoveryInputs) -> RecoveryResult {
        var parts: [(key: String, value: Double)] = []

        let sleep = sleepScore(i)
        let hrv = hrvScore(i)
        let rhr = rhrScore(i)
        let load = loadScore(i)

        if let s = sleep { parts.append(("sleep", s)) }
        if let s = hrv { parts.append(("hrv", s)) }
        if let s = rhr { parts.append(("rhr", s)) }
        if let s = load { parts.append(("load", s)) }

        let totalWeight = parts.reduce(0) { $0 + (Self.weights[$1.key] ?? 0) }
        let score: Double = totalWeight == 0
            ? 50
            : parts.reduce(0) { $0 + (Self.weights[$1.key] ?? 0) * $1.value } / totalWeight * 100

        return RecoveryResult(
            score: score.rounded(),
            recommendation: recommendation(for: score),
            sleepScore: sleep.map { ($0 * 100).rounded() },
            hrvScore: hrv.map { ($0 * 100).rounded() },
            rhrScore: rhr.map { ($0 * 100).rounded() },
            loadScore: load.map { ($0 * 100).rounded() },
            dataCompleteness: Double(parts.count) / 4
        )
    }

    // MARK: - Sub-scores (0…1)

    private func sleepScore(_ i: RecoveryInputs) -> Double? {
        guard let asleep = i.asleepMinutes else { return nil }
        let durationRatio = (Double(asleep) / Double(i.sleepNeedMinutes)).clamped(to: 0...1.1)
        let duration = min(durationRatio, 1)            // no bonus for oversleeping
        let efficiency = i.sleepEfficiency?.clamped(to: 0...1) ?? 0.9
        return (0.7 * duration + 0.3 * efficiency).clamped(to: 0...1)
    }

    /// Above baseline HRV is good; below is bad. Mapped via z-score.
    private func hrvScore(_ i: RecoveryInputs) -> Double? {
        guard let v = i.hrv, let m = i.hrvBaselineMean, let sd = i.hrvBaselineSD, sd > 0
        else { return nil }
        let z = (v - m) / sd
        return sigmoid(z).clamped(to: 0...1)
    }

    /// Elevated resting HR indicates suppressed recovery → inverse z-score.
    private func rhrScore(_ i: RecoveryInputs) -> Double? {
        guard let v = i.restingHR, let m = i.rhrBaselineMean, let sd = i.rhrBaselineSD, sd > 0
        else { return nil }
        let z = (v - m) / sd
        return sigmoid(-z).clamped(to: 0...1)
    }

    /// Acute:chronic workload ratio. Sweet spot ~0.8–1.3; >1.5 penalized hard.
    private func loadScore(_ i: RecoveryInputs) -> Double? {
        guard let acute = i.acuteLoad, let chronic = i.chronicLoad, chronic > 0
        else { return nil }
        let acwr = acute / chronic
        switch acwr {
        case ..<0.8: return 0.9                      // detraining, but recovered
        case 0.8...1.3: return 1.0
        case 1.3...1.5: return 0.7
        default: return max(0, 1.0 - (acwr - 1.5))
        }
    }

    private func recommendation(for score: Double) -> TrainingRecommendation {
        switch score {
        case 90...: return .pushIntensity
        case 70..<90: return .normalTraining
        case 50..<70: return .reduceVolume
        default: return .recoveryFocus
        }
    }

    /// Logistic squash centered so baseline (z=0) maps to 0.5.
    private func sigmoid(_ z: Double) -> Double { 1 / (1 + exp(-z)) }
}
