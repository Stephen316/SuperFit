import Foundation

/// One daily observation, indexed by whole days from an arbitrary origin.
struct CyclicalSample: Sendable {
    let day: Int
    let value: Double
}

/// A recurring rhythm found in a recovery marker, with the per-phase offsets
/// needed to remove it.
struct CyclicalPattern: Sendable {
    let periodDays: Int
    let cyclesObserved: Int
    /// Adjusted R² of the folded profile, 0…1 — how much of the marker's
    /// variation the rhythm accounts for.
    let strength: Double
    /// Peak-to-trough of the phase profile, in the marker's own units
    /// (ms for HRV, bpm for resting HR).
    let amplitude: Double
    /// Smoothed deviation at each phase position, indexed 0..<periodDays.
    let profile: [Double]

    /// Correction is scaled back until enough cycles have been seen to trust the
    /// period. A period estimated one day short drifts a day out of phase per
    /// cycle, and a confidently misaligned correction is worse than a timid one;
    /// simulation showed partial correction beating full at short windows and
    /// matching it once six cycles are in.
    var confidence: Double { min(1, Double(cyclesObserved) / 6) }

    /// How much this day is expected to sit above or below the person's own
    /// average purely because of where it falls in the cycle.
    func offset(forDay day: Int) -> Double {
        guard !profile.isEmpty else { return 0 }
        let phase = ((day % periodDays) + periodDays) % periodDays
        return profile[phase] * confidence
    }
}

/// Finds a repeating multi-week rhythm in a recovery marker and removes it from
/// the baseline comparison.
///
/// Why this exists: HRV and resting heart rate are scored as z-scores against a
/// flat 60-day mean and SD. For anyone with a genuine cyclical physiology — most
/// obviously the menstrual cycle, where HRV falls and resting HR rises by
/// 2–5 bpm through the luteal phase — that flat baseline does two harmful
/// things. It inflates the SD, blunting real signal all month; and it pushes one
/// phase systematically negative, so the app reports "reduce volume" on schedule
/// every month for no physiological reason. Acting on that advice would mean
/// cutting training every cycle without cause.
///
/// The rhythm is inferred from the recovery data itself rather than from logged
/// period dates, so it needs nothing extra from the user and works for people who
/// don't track cycles. Nothing here identifies *what* the rhythm is — it detects
/// that a marker repeats on a 21–35 day period and levels the baseline
/// accordingly. See docs/ALGORITHMS.md §3.
enum CyclicalBaseline {

    /// Physiological bounds for a menstrual cycle. Outside this range a repeat
    /// is more likely training periodisation, shift patterns, or noise.
    static let periodRange = 21...35
    /// Candidate rhythms below the physiological floor, tested only to be ruled
    /// out. A 7-day rhythm folds perfectly at 21, 28 and 35 because it divides
    /// all three, so `periodRange` alone excludes 7 as an *answer* while letting
    /// it arrive disguised as a multiple of itself.
    static let subPhysiologicalRange = 2...20
    /// Reject the monthly candidate when a sub-physiological period explains at
    /// least this much of its strength. Measured safe over 0.70–0.95; 0.85 is
    /// the middle of that plateau rather than either edge.
    static let maxHarmonicRatio = 0.85
    /// Evidence bar before adjusting anything: at least this many complete
    /// repeats, spanning at least `minSpanDays`. A pattern seen once or twice is
    /// a coincidence; the point is to be slow rather than clever.
    static let minCycles = 3
    static let minSpanDays = 90
    /// Minimum adjusted R² for the folded profile. Physiological rhythms sit in
    /// a lot of night-to-night noise, so this is modest — the amplitude gate
    /// below has to clear too. Measured false-positive rate on rhythm-free data
    /// (flat, drifting, and weak-signal): 0%.
    static let minStrength = 0.10
    /// The swing must be worth correcting: at least a third of the marker's own
    /// residual spread, otherwise removing it is churn.
    static let minAmplitudeRatio = 0.33

    /// Returns a pattern only when the evidence bar is met, otherwise nil.
    static func detect(_ samples: [CyclicalSample]) -> CyclicalPattern? {
        guard samples.count >= 45,
              let first = samples.min(by: { $0.day < $1.day })?.day,
              let last = samples.max(by: { $0.day < $1.day })?.day,
              last - first >= minSpanDays
        else { return nil }

        // Remove slow drift first: months of rising fitness lift HRV steadily,
        // and that trend would otherwise dominate the autocorrelation.
        let residuals = detrended(samples)
        let spread = standardDeviation(residuals.map(\.value))
        guard spread > 0 else { return nil }

        // Pick the period whose folded profile explains the most variance, rather
        // than the autocorrelation peak. Both find a rhythm, but only this one
        // optimises the quantity actually used downstream — and it matters: an
        // autocorrelation peak recovered the true period 0% of the time on
        // realistic noise (28 d read as 25), while this recovers it exactly on
        // 82–99% of windows of six cycles or more.
        guard let best = bestFit(residuals, over: periodRange, span: last - first),
              best.strength >= minStrength
        else { return nil }

        let amplitude = (best.profile.max() ?? 0) - (best.profile.min() ?? 0)
        guard amplitude >= minAmplitudeRatio * spread else { return nil }

        // Harmonic guard. Asking whether the profile repeats within itself fires
        // on any smooth rhythm — rotating a smooth curve by a day barely changes
        // it. The question that separates the cases is whether a *shorter* period
        // explains the residuals about as well: for a genuine monthly rhythm the
        // best sub-21 fit is near zero adjusted R², while for an aliased weekly
        // one it edges ahead of the monthly candidate.
        if let short = bestFit(residuals, over: subPhysiologicalRange, span: last - first),
           short.strength >= best.strength * maxHarmonicRatio {
            return nil
        }

        return CyclicalPattern(periodDays: best.period,
                               cyclesObserved: (last - first) / best.period,
                               strength: best.strength,
                               amplitude: amplitude,
                               profile: best.profile)
    }

    /// Strongest folded fit across a range of candidate periods.
    private static func bestFit(_ residuals: [CyclicalSample],
                                over periods: ClosedRange<Int>,
                                span: Int) -> (period: Int, strength: Double, profile: [Double])? {
        var best: (period: Int, strength: Double, profile: [Double])?
        for period in periods {
            guard span / period >= minCycles,
                  let candidate = foldedProfile(residuals, period: period)
            else { continue }
            if best == nil || candidate.strength > best!.strength {
                best = (period, candidate.strength, candidate.profile)
            }
        }
        return best
    }

    /// Folds the series onto one cycle of `period` and reports the phase profile
    /// with the adjusted R² it achieves.
    private static func foldedProfile(_ residuals: [CyclicalSample],
                                      period: Int) -> (profile: [Double], strength: Double)? {
        var bins: [[Double]] = Array(repeating: [], count: period)
        for r in residuals {
            bins[((r.day % period) + period) % period].append(r.value)
        }
        // Every phase position needs evidence from more than one cycle.
        guard bins.allSatisfy({ $0.count >= 2 }) else { return nil }

        // Median per phase, then a circular 5-point mean: the underlying rhythm
        // is smooth, so the profile should be too, and smoothing both denoises it
        // and cuts the effective parameter count.
        let raw = bins.map(median)
        let profile = (0..<period).map { i in
            [-2, -1, 0, 1, 2]
                .map { raw[((i + $0) % period + period) % period] }
                .reduce(0, +) / 5
        }

        let values = residuals.map(\.value)
        let totalVariance = variance(values)
        guard totalVariance > 0 else { return nil }
        let leftover = variance(residuals.map {
            $0.value - profile[(($0.day % period) + period) % period]
        })
        let r2 = 1 - leftover / totalVariance

        // Adjusted for the parameters spent: a longer period fits more freely and
        // would otherwise always win. Smoothing ties neighbouring phases
        // together, so the effective count is well below `period`.
        let n = Double(residuals.count)
        let k = Double(period) / 3
        guard n - k - 1 > 0 else { return nil }
        let adjusted = 1 - (1 - r2) * (n - 1) / (n - k - 1)
        return (profile, adjusted)
    }

    /// Levels the series by removing the cyclical component, so the mean and SD
    /// taken from it describe ordinary variation rather than the rhythm.
    static func levelled(_ samples: [CyclicalSample],
                         pattern: CyclicalPattern) -> [CyclicalSample] {
        samples.map { CyclicalSample(day: $0.day, value: $0.value - pattern.offset(forDay: $0.day)) }
    }

    // MARK: - Internals

    /// Subtracts a robust straight line, so long-run drift doesn't read as rhythm.
    private static func detrended(_ samples: [CyclicalSample]) -> [CyclicalSample] {
        let sorted = samples.sorted { $0.day < $1.day }
        guard sorted.count >= 2 else { return sorted }

        // Theil–Sen on a thinned pair set: full pairwise is O(n²) and n can be
        // several hundred days here, which is wasteful for a nuisance parameter.
        let stride = max(1, sorted.count / 60)
        let thinned = Swift.stride(from: 0, to: sorted.count, by: stride).map { sorted[$0] }
        var slopes: [Double] = []
        for i in 0..<thinned.count {
            for j in (i + 1)..<thinned.count where thinned[j].day != thinned[i].day {
                slopes.append(Double(thinned[j].value - thinned[i].value)
                              / Double(thinned[j].day - thinned[i].day))
            }
        }
        let slope = slopes.isEmpty ? 0 : median(slopes)
        let intercept = median(sorted.map { $0.value - slope * Double($0.day) })
        return sorted.map {
            CyclicalSample(day: $0.day, value: $0.value - (intercept + slope * Double($0.day)))
        }
    }

    private static func median(_ xs: [Double]) -> Double {
        guard !xs.isEmpty else { return 0 }
        let s = xs.sorted()
        let mid = s.count / 2
        return s.count.isMultiple(of: 2) ? (s[mid - 1] + s[mid]) / 2 : s[mid]
    }

    private static func variance(_ xs: [Double]) -> Double {
        guard xs.count > 1 else { return 0 }
        let mean = xs.reduce(0, +) / Double(xs.count)
        return xs.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(xs.count - 1)
    }

    private static func standardDeviation(_ xs: [Double]) -> Double {
        variance(xs).squareRoot()
    }
}
