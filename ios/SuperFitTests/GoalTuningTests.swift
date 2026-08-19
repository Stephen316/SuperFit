import Testing
import Foundation
@testable import SuperFit

/// The strength goal (#27) and per-goal tuning/guidance (#28).
struct GoalTuningTests {

    @Test func strengthGoalExistsAndIsSelectable() {
        #expect(FitnessGoal.allCases.contains(.strength))
    }

    @Test func strengthSitsAtASmallSurplusBelowMuscleGain() {
        #expect(FitnessGoal.strength.calorieOffset == 0.05)
        // Above maintenance, below a full muscle-gain bulk.
        #expect(FitnessGoal.strength.calorieOffset > FitnessGoal.maintenance.calorieOffset)
        #expect(FitnessGoal.strength.calorieOffset < FitnessGoal.muscleGain.calorieOffset)
    }

    @Test func strengthProteinMatchesTheGainGroup() {
        #expect(FitnessGoal.strength.defaultProtein(perLeanMass: false) == 1.8)
        #expect(FitnessGoal.strength.defaultProtein(perLeanMass: true) == 2.2)
    }

    @Test func strengthTrainsLowRepEverythingElseModerate() {
        #expect(FitnessGoal.strength.repTarget == 3)
        for goal in FitnessGoal.allCases where goal != .strength {
            #expect(goal.repTarget == 8)
        }
    }

    @Test func everyGoalHasANonEmptyDistinctTip() {
        let tips = FitnessGoal.allCases.map { GoalGuidance.tip(for: $0) }
        #expect(tips.allSatisfy { !$0.isEmpty })
        #expect(Set(tips).count == FitnessGoal.allCases.count)   // one per goal, all distinct
    }
}
