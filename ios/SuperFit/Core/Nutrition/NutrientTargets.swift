import Foundation

struct NutrientTarget: Sendable {
    let nutrient: Micronutrient
    let amount: Double
    let isLimit: Bool
    /// Set when the value departs from the standard reference intake.
    let reason: String?
}

/// Daily micronutrient targets: US/EU reference intakes as the base, adjusted
/// for the demands resistance training actually creates.
///
/// Sources: NIH Office of Dietary Supplements DRI tables (adult RDAs);
/// sodium/saturated-fat/sugar ceilings from WHO and the US Dietary Guidelines.
/// Training adjustments follow the sports-nutrition literature — see
/// docs/ALGORITHMS.md §5.
struct NutrientTargets: Sendable {

    struct Inputs: Sendable {
        var sex: BiologicalSex
        var ageYears: Int
        var kcalTarget: Double
        var goal: FitnessGoal
        /// Weekly hard training sessions; drives sweat-loss adjustments.
        var sessionsPerWeek: Int = 0
    }

    func targets(_ i: Inputs) -> [NutrientTarget] {
        let female = i.sex == .female
        let training = i.sessionsPerWeek >= 3
        let over50 = i.ageYears > 50

        var out: [NutrientTarget] = []
        func add(_ n: Micronutrient, _ amount: Double, _ reason: String? = nil) {
            out.append(NutrientTarget(nutrient: n, amount: amount,
                                      isLimit: n.isLimit, reason: reason))
        }

        // Ceilings scale with intake, since they are proportions of the diet.
        add(.saturatedFat, i.kcalTarget * 0.10 / 9)          // <10% of energy
        add(.sugar, i.kcalTarget * 0.10 / 4)                 // WHO free-sugar limit
        add(.cholesterol, 300)

        // Sodium: 2300 mg ceiling, raised for heavy sweat loss. Athletes losing
        // ~1 g/L of sweat need more than the sedentary limit, not less.
        if training {
            add(.sodium, 3000, "Raised for sweat losses from \(i.sessionsPerWeek) sessions/wk")
        } else {
            add(.sodium, 2300)
        }

        // Potassium: RDA 3400 m / 2600 f. Lifters cramp on low potassium and
        // most people under-consume it, so training nudges it up.
        let potassium = female ? 2600.0 : 3400.0
        add(.potassium, training ? potassium * 1.15 : potassium,
            training ? "Raised for training sweat losses" : nil)

        // Calcium: 1000 mg, 1200 for women over 50. A calorie deficit raises
        // bone-turnover risk, so hold the higher figure when cutting.
        let cuttingHard = i.goal == .fatLoss
        if over50 && female {
            add(.calcium, 1200, "Higher after 50")
        } else if cuttingHard {
            add(.calcium, 1200, "Protects bone density in a deficit")
        } else {
            add(.calcium, 1000)
        }

        // Iron: 18 mg premenopausal women vs 8 mg men. Endurance-heavy training
        // adds losses through foot-strike haemolysis and sweat.
        let iron = (female && !over50) ? 18.0 : 8.0
        add(.iron, training ? iron * 1.3 : iron,
            training ? "Raised for training-related losses" : nil)

        add(.magnesium, female ? 320 : 420)
        add(.zinc, female ? 8 : 11)

        add(.vitaminC, female ? 75 : 90)
        add(.vitaminD, over50 ? 20 : 15, over50 ? "Higher after 50" : nil)
        add(.vitaminA, female ? 700 : 900)
        add(.vitaminB12, 2.4)
        add(.folate, 400)

        return out
    }
}
