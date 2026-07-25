import Foundation
import SwiftData

/// Built-in exercise catalog with muscle-tension scores (1–5: how much tension
/// the muscle experiences in the lift; 5 = prime mover at long length /
/// maximal load, 1 = lightly assisting). Seeded into SwiftData on first launch.
enum ExerciseLibrary {

    typealias T = [MuscleGroup: Int]

    /// Fraction of bodyweight moved, for the bodyweight entries. Values are
    /// the standard biomechanics estimates: a pull-up/dip moves essentially all
    /// of you, a push-up ~65% (feet bear the rest), a plank is isometric so it
    /// carries no rep-based tonnage.
    static let catalog: [(String, ExerciseCategory, T, Double)] = [
        // Chest
        ("Barbell Bench Press", .barbell, [.chest: 5, .triceps: 3, .shoulders: 2], 0),
        ("Incline Barbell Press", .barbell, [.chest: 5, .shoulders: 3, .triceps: 3], 0),
        ("Flat Dumbbell Press", .dumbbell, [.chest: 5, .triceps: 3, .shoulders: 2], 0),
        ("Incline Dumbbell Press", .dumbbell, [.chest: 5, .shoulders: 3, .triceps: 2], 0),
        ("Machine Chest Press", .machine, [.chest: 5, .triceps: 3, .shoulders: 2], 0),
        ("Cable Fly", .cable, [.chest: 5, .shoulders: 1], 0),
        ("Pec Deck", .machine, [.chest: 5], 0),
        ("Dip", .bodyweight, [.chest: 4, .triceps: 4, .shoulders: 2], 1.0),
        ("Push-Up", .bodyweight, [.chest: 4, .triceps: 3, .shoulders: 2, .core: 2], 0.65),
        // Shoulders
        ("Overhead Press", .barbell, [.shoulders: 5, .triceps: 3, .core: 2], 0),
        ("Seated Dumbbell Press", .dumbbell, [.shoulders: 5, .triceps: 3], 0),
        ("Lateral Raise", .dumbbell, [.shoulders: 5], 0),
        ("Cable Lateral Raise", .cable, [.shoulders: 5], 0),
        ("Rear Delt Fly", .dumbbell, [.shoulders: 4, .traps: 2], 0),
        ("Face Pull", .cable, [.shoulders: 3, .traps: 3, .back: 2], 0),
        ("Front Raise", .dumbbell, [.shoulders: 4], 0),
        // Back
        ("Deadlift", .barbell, [.lowerBack: 5, .glutes: 4, .hamstrings: 4, .back: 3, .traps: 3, .forearms: 2, .core: 2], 0),
        ("Rack Pull", .barbell, [.lowerBack: 4, .traps: 4, .back: 3, .forearms: 3], 0),
        ("Barbell Row", .barbell, [.back: 5, .biceps: 3, .lowerBack: 2, .forearms: 2], 0),
        ("Dumbbell Row", .dumbbell, [.back: 5, .biceps: 3, .forearms: 2], 0),
        ("Pull-Up", .bodyweight, [.back: 5, .biceps: 3, .forearms: 2, .core: 1], 1.0),
        ("Chin-Up", .bodyweight, [.back: 4, .biceps: 4, .forearms: 2], 1.0),
        ("Lat Pulldown", .cable, [.back: 5, .biceps: 3], 0),
        ("Seated Cable Row", .cable, [.back: 5, .biceps: 3, .traps: 2], 0),
        ("T-Bar Row", .machine, [.back: 5, .biceps: 3, .lowerBack: 2], 0),
        ("Straight-Arm Pulldown", .cable, [.back: 4, .triceps: 1], 0),
        ("Barbell Shrug", .barbell, [.traps: 5, .forearms: 2], 0),
        ("Back Extension", .bodyweight, [.lowerBack: 4, .glutes: 3, .hamstrings: 3], 0.45),
        // Biceps
        ("Barbell Curl", .barbell, [.biceps: 5, .forearms: 2], 0),
        ("Dumbbell Curl", .dumbbell, [.biceps: 5, .forearms: 2], 0),
        ("Hammer Curl", .dumbbell, [.biceps: 4, .forearms: 3], 0),
        ("Preacher Curl", .machine, [.biceps: 5], 0),
        ("Incline Dumbbell Curl", .dumbbell, [.biceps: 5], 0),
        ("Cable Curl", .cable, [.biceps: 5, .forearms: 2], 0),
        // Triceps
        ("Triceps Pushdown", .cable, [.triceps: 5], 0),
        ("Overhead Triceps Extension", .cable, [.triceps: 5], 0),
        ("Skull Crusher", .barbell, [.triceps: 5], 0),
        ("Close-Grip Bench Press", .barbell, [.triceps: 4, .chest: 3, .shoulders: 2], 0),
        // Quads
        ("Barbell Squat", .barbell, [.quads: 5, .glutes: 4, .lowerBack: 2, .core: 2], 0),
        ("Front Squat", .barbell, [.quads: 5, .glutes: 3, .core: 3], 0),
        ("Leg Press", .machine, [.quads: 5, .glutes: 3], 0),
        ("Hack Squat", .machine, [.quads: 5, .glutes: 3], 0),
        ("Leg Extension", .machine, [.quads: 5], 0),
        ("Bulgarian Split Squat", .dumbbell, [.quads: 5, .glutes: 4, .core: 1], 0.85),
        ("Walking Lunge", .dumbbell, [.quads: 4, .glutes: 4, .hamstrings: 2, .core: 1], 0.85),
        ("Goblet Squat", .dumbbell, [.quads: 4, .glutes: 3, .core: 2], 0),
        // Hamstrings / glutes
        ("Romanian Deadlift", .barbell, [.hamstrings: 5, .glutes: 4, .lowerBack: 3, .forearms: 2], 0),
        ("Lying Leg Curl", .machine, [.hamstrings: 5], 0),
        ("Seated Leg Curl", .machine, [.hamstrings: 5], 0),
        ("Hip Thrust", .barbell, [.glutes: 5, .hamstrings: 3, .quads: 1], 0),
        ("Glute Bridge", .bodyweight, [.glutes: 4, .hamstrings: 2], 0.35),
        ("Good Morning", .barbell, [.hamstrings: 4, .lowerBack: 4, .glutes: 3], 0),
        ("Cable Kickback", .cable, [.glutes: 4], 0),
        // Calves
        ("Standing Calf Raise", .machine, [.calves: 5], 0),
        ("Seated Calf Raise", .machine, [.calves: 5], 0),
        // Core
        ("Plank", .bodyweight, [.core: 4], 0.0),
        ("Cable Crunch", .cable, [.core: 5], 0),
        ("Hanging Leg Raise", .bodyweight, [.core: 5, .forearms: 1], 0.45),
        ("Ab Wheel Rollout", .bodyweight, [.core: 5, .shoulders: 1], 0.45),
    ]

    @MainActor
    static func seedIfNeeded(context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        if existing.isEmpty {
            for (name, category, tension, fraction) in catalog {
                context.insert(Exercise(name: name, category: category, tension: tension,
                                        bodyweightFraction: fraction))
            }
            try? context.save()
            return
        }
        // Migrate rows written before tension / bodyweight-fraction existed, and
        // add newly-catalogued exercises by name.
        let byName = Dictionary(grouping: existing, by: \.name)
        var changed = false
        for (name, category, tension, fraction) in catalog {
            if let row = byName[name]?.first {
                if row.tensionRaw.isEmpty {
                    row.tension = tension
                    changed = true
                }
                if row.bodyweightFraction != fraction {
                    row.bodyweightFraction = fraction
                    changed = true
                }
            } else {
                context.insert(Exercise(name: name, category: category, tension: tension,
                                        bodyweightFraction: fraction))
                changed = true
            }
        }
        if changed { try? context.save() }
    }
}
