import Foundation

struct MacroTargets: Sendable, Equatable {
    let kcal: Double
    let proteinG: Double
    let fatG: Double
    let carbG: Double
    let fibreG: Double
}

/// Turns a calorie target + body composition into a macro split.
/// Order: protein → fat floor → carbs fill remainder. See docs/ALGORITHMS.md §2.
struct MacroCalculator: Sendable {

    func targets(kcal: Double,
                 goal: FitnessGoal,
                 bodyweightKg: Double,
                 leanMassKg: Double? = nil,
                 proteinPerKg: Double? = nil) -> MacroTargets {

        let proteinBasis = leanMassKg ?? bodyweightKg
        let gPerKg = proteinPerKg ?? goal.defaultProteinPerKg
        let proteinG = (gPerKg * proteinBasis).rounded()

        let fatFloor = max(0.8 * bodyweightKg, 0.25 * kcal / 9)
        let fatG = fatFloor.rounded()

        let remaining = kcal - 4 * proteinG - 9 * fatG
        let carbG = max(50, remaining / 4).rounded()

        // Fibre target scales with intake (14 g / 1000 kcal, USDA guidance).
        let fibreG = (14 * kcal / 1000).rounded()

        return MacroTargets(kcal: kcal.rounded(),
                            proteinG: proteinG,
                            fatG: fatG,
                            carbG: carbG,
                            fibreG: fibreG)
    }
}
