import Foundation

/// Decides when a lifter is recovered enough to start the next set, from heart
/// rate rather than a fixed clock — the core of the HR-based rest feature (#26).
///
/// The v1 heuristic: the next set is advised once HR has fallen a set fraction of
/// the way from the set's peak back toward a resting baseline, or — with no
/// baseline known — once it has dropped a fixed margin below the peak. A floor
/// stops it saying "ready" the instant a set ends; a cap stops an unreachable
/// target (sensor gap, very high baseline) from trapping the user resting.
///
/// Pure and Sendable so it's testable off-watch, like the app's other engines.
struct HRRestAdvisor: Sendable {
    /// Fraction of the peak→baseline drop that counts as recovered — 0.5 means
    /// HR halfway back down to baseline.
    var recoveryFraction: Double = 0.5
    /// With no baseline, "recovered" is this many bpm below the set's peak.
    var fallbackDropBpm: Double = 25
    /// Never advise the next set before this, however fast HR falls.
    var minRest: TimeInterval = 30
    /// Advise the next set by this point even if HR hasn't reached target.
    var maxRest: TimeInterval = 240

    enum Readiness: String, Sendable { case resting, ready }

    /// HR at or below which the next set is advised.
    func targetHR(peakHR: Double, baselineHR: Double?) -> Double {
        if let baseline = baselineHR, peakHR > baseline {
            return baseline + (peakHR - baseline) * (1 - recoveryFraction)
        }
        return peakHR - fallbackDropBpm
    }

    func readiness(currentHR: Double?, peakHR: Double,
                   baselineHR: Double?, elapsed: TimeInterval) -> Readiness {
        if elapsed >= maxRest { return .ready }        // capped: don't rest forever
        if elapsed < minRest { return .resting }       // floored: catch your breath
        guard let currentHR else { return .resting }   // no HR yet → keep resting
        return currentHR <= targetHR(peakHR: peakHR, baselineHR: baselineHR)
            ? .ready : .resting
    }
}

/// Records the HR at which the user actually resumed each set, so a later version
/// can personalise the target ("you usually start again around 96"). v1 only
/// accumulates and reports the median — the advisor still drives readiness — but
/// this is the data that makes learning possible once enough sessions exist.
/// Persisted so it survives across sessions.
struct ResumeHRStore {
    private let defaults: UserDefaults
    private let key = "resumeHR.samples.v1"
    private let maxSamples = 200

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func record(_ hr: Double) {
        guard hr > 0 else { return }
        var samples = defaults.array(forKey: key) as? [Double] ?? []
        samples.append(hr)
        if samples.count > maxSamples { samples.removeFirst(samples.count - maxSamples) }
        defaults.set(samples, forKey: key)
    }

    var samples: [Double] { defaults.array(forKey: key) as? [Double] ?? [] }

    /// The user's typical resume HR, once enough sessions exist to mean anything.
    func learnedResumeHR(minSamples: Int = 5) -> Double? {
        let sorted = samples.sorted()
        guard sorted.count >= minSamples else { return nil }
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }
}
