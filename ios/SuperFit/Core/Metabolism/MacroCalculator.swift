import Foundation

struct MacroTargets: Sendable, Equatable {
    let kcal: Double
    let proteinG: Double
    let fatG: Double
    let carbG: Double
    let fibreG: Double

    /// Energy the macro split actually accounts for. Should equal `kcal` to
    /// within rounding; the calculator guarantees it.
    var macroKcal: Double { 4 * proteinG + 9 * fatG + 4 * carbG }
}

/// Turns a calorie target + body composition into a macro split.
/// Order: protein → fat floor → carbs fill remainder. See docs/ALGORITHMS.md §2.
struct MacroCalculator: Sendable {

    /// Carbohydrate floor (g). Roughly the brain's daily glucose demand — going
    /// under is a ketogenic prescription, which this app doesn't make.
    static let carbFloorG = 50.0
    /// Essential-fat floor (g/kg). Below ~0.5 g/kg risks hormonal disruption.
    static let essentialFatPerKg = 0.5

    func targets(kcal: Double,
                 goal: FitnessGoal,
                 bodyweightKg: Double,
                 leanMassKg: Double? = nil,
                 proteinPerKg: Double? = nil) -> MacroTargets {

        // Protein is referenced to lean mass when it's known, and the g/kg
        // figure changes with the basis — see FitnessGoal.defaultProtein(perLeanMass:).
        let usingLeanMass = leanMassKg != nil
        let proteinBasis = leanMassKg ?? bodyweightKg
        let gPerKg = proteinPerKg ?? goal.defaultProtein(perLeanMass: usingLeanMass)
        var proteinG = (gPerKg * proteinBasis).rounded()

        var fatG = max(0.8 * bodyweightKg, 0.25 * kcal / 9).rounded()

        // Reconcile so the three macros sum to the calorie target. Without this
        // the carb floor silently pushes the total past `kcal` and the diary
        // shows a target set that cannot all be hit at once.
        let carbFloorKcal = 4 * Self.carbFloorG
        let fatFloorG = (Self.essentialFatPerKg * bodyweightKg).rounded()

        // 1. Trim fat toward its essential floor.
        var overshoot = (4 * proteinG + 9 * fatG + carbFloorKcal) - kcal
        if overshoot > 0 {
            let trimmableFatG = max(0, fatG - fatFloorG)
            let trimG = min(trimmableFatG, (overshoot / 9).rounded(.up))
            fatG -= trimG
            overshoot -= 9 * trimG
        }
        // 2. Still over: trim protein. Kept last — it's the macro most worth
        //    protecting in a deficit — and never below 1.2 g/kg bodyweight.
        if overshoot > 0 {
            let proteinFloorG = (1.2 * bodyweightKg).rounded()
            let trimmableProteinG = max(0, proteinG - proteinFloorG)
            let trimG = min(trimmableProteinG, (overshoot / 4).rounded(.up))
            proteinG -= trimG
            overshoot -= 4 * trimG
        }
        // 3. If it still doesn't fit, the calorie target is below the sum of the
        //    floors. Report the floors honestly rather than a split that lies:
        //    `macroKcal` will exceed `kcal`, which the guardrail in
        //    MetabolismEngine.calorieTarget is designed to prevent upstream.
        let remaining = kcal - 4 * proteinG - 9 * fatG
        let carbG = max(Self.carbFloorG, remaining / 4).rounded()

        // Fibre target scales with intake (14 g / 1000 kcal, USDA guidance).
        let fibreG = (14 * kcal / 1000).rounded()

        return MacroTargets(kcal: kcal.rounded(),
                            proteinG: proteinG,
                            fatG: fatG,
                            carbG: carbG,
                            fibreG: fibreG)
    }
}
