import Foundation

/// A live "energy level" — a body-battery-style 0–100 read of how much you have
/// left in the tank right now, in the spirit of Garmin's Body Battery.
///
/// This is an **openly heuristic composite**, not a validated measurement, and is
/// kept out of every scored figure the app stands behind. It combines what is
/// already known: the morning charge you woke with (recovery), how far the day has
/// drawn it down (the clock and today's exertion), and whether you are fuelled. It
/// degrades to whatever exists — with no watch it still reads from phone steps,
/// activity energy and the food diary — and reports no data only when nothing at
/// all is available.
///
/// Charge, then drain:
///   energy = morningCharge − circadianDrain − exertionDrain − fuelDeficit
struct EnergyEngine: Sendable {

    /// Points the day drains simply from being awake, wake to end of day. Stops a
    /// fully rested, restful day from still reading 100% at bedtime.
    static let maxCircadianDrain = 22.0
    /// A maximal day's exertion draws this down on top of the clock.
    static let maxExertionDrain = 35.0
    /// The neutral charge assumed when recovery is unknown — "probably rested",
    /// neither rewarded nor penalised.
    static let neutralCharge = 72.0

    enum Band: String, Sendable {
        case drained = "Drained"
        case low = "Low"
        case steady = "Steady"
        case charged = "Charged"
    }

    struct Inputs: Sendable {
        var recoveryScore: Double?     // 0…100, the morning charge
        var strain: Double?            // 0…100, today's exertion
        var activeEnergyKcal: Double?  // today so far; exertion proxy without strain
        var steps: Int?                // exertion proxy without either
        var intakeKcal: Double?        // consumed so far
        var targetKcal: Double?        // the day's calorie target
        var dayFraction: Double        // 0…1 of the waking day elapsed
    }

    struct Result: Sendable, Equatable {
        let level: Double              // 0…100, rounded
        let band: Band
        let dataCompleteness: Double   // fraction of the three optional signals present
    }

    func evaluate(_ i: Inputs) -> Result? {
        var signals = 0
        var energy = i.recoveryScore ?? Self.neutralCharge
        if i.recoveryScore != nil { signals += 1 }

        let frac = clamped01(i.dayFraction)
        energy -= Self.maxCircadianDrain * frac

        // Exertion: prefer measured strain, fall back to activity energy, then to
        // steps — non-exercise movement drains more gently than logged training.
        if let strain = i.strain {
            energy -= Self.maxExertionDrain * clamped01(strain / 100)
            signals += 1
        } else if let active = i.activeEnergyKcal {
            energy -= 25 * clamped01(active / 600)
            signals += 1
        } else if let steps = i.steps {
            energy -= 20 * clamped01(Double(steps) / 12_000)
            signals += 1
        }

        // Under-fuelling for the time of day drains a little. Judged only once
        // there is logged intake and enough of the day has passed to have a pace
        // to fall behind — an empty morning diary is unknown, not under-fuelled.
        if let intake = i.intakeKcal, let target = i.targetKcal,
           target > 0, intake > 0, frac > 0.3 {
            let ratio = intake / (target * frac)
            energy += max(-10, min(0, (ratio - 1) * 12))
            signals += 1
        }

        guard signals > 0 else { return nil }
        let level = min(100, max(0, energy)).rounded()
        return Result(level: level, band: band(for: level),
                      dataCompleteness: Double(signals) / 3)
    }

    private func band(for level: Double) -> Band {
        switch level {
        case ..<20: return .drained
        case ..<40: return .low
        case ..<70: return .steady
        default: return .charged
        }
    }

    private func clamped01(_ x: Double) -> Double { min(max(x, 0), 1) }
}
