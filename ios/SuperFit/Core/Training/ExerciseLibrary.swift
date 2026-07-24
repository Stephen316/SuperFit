import Foundation
import SwiftData

/// Built-in exercise catalog with muscle-tension scores (1–5: how much tension
/// the muscle experiences in the lift; 5 = prime mover at long length /
/// maximal load, 1 = lightly assisting). Seeded into SwiftData on first launch.
enum ExerciseLibrary {

    typealias T = [MuscleGroup: Int]

    static let catalog: [(String, ExerciseCategory, T)] = [
        // Chest
        ("Barbell Bench Press", .barbell, [.chest: 5, .triceps: 3, .shoulders: 2]),
        ("Incline Barbell Press", .barbell, [.chest: 5, .shoulders: 3, .triceps: 3]),
        ("Flat Dumbbell Press", .dumbbell, [.chest: 5, .triceps: 3, .shoulders: 2]),
        ("Incline Dumbbell Press", .dumbbell, [.chest: 5, .shoulders: 3, .triceps: 2]),
        ("Machine Chest Press", .machine, [.chest: 5, .triceps: 3, .shoulders: 2]),
        ("Cable Fly", .cable, [.chest: 5, .shoulders: 1]),
        ("Pec Deck", .machine, [.chest: 5]),
        ("Dip", .bodyweight, [.chest: 4, .triceps: 4, .shoulders: 2]),
        ("Push-Up", .bodyweight, [.chest: 4, .triceps: 3, .shoulders: 2, .core: 2]),
        // Shoulders
        ("Overhead Press", .barbell, [.shoulders: 5, .triceps: 3, .core: 2]),
        ("Seated Dumbbell Press", .dumbbell, [.shoulders: 5, .triceps: 3]),
        ("Lateral Raise", .dumbbell, [.shoulders: 5]),
        ("Cable Lateral Raise", .cable, [.shoulders: 5]),
        ("Rear Delt Fly", .dumbbell, [.shoulders: 4, .traps: 2]),
        ("Face Pull", .cable, [.shoulders: 3, .traps: 3, .back: 2]),
        ("Front Raise", .dumbbell, [.shoulders: 4]),
        // Back
        ("Deadlift", .barbell, [.lowerBack: 5, .glutes: 4, .hamstrings: 4, .back: 3, .traps: 3, .forearms: 2, .core: 2]),
        ("Rack Pull", .barbell, [.lowerBack: 4, .traps: 4, .back: 3, .forearms: 3]),
        ("Barbell Row", .barbell, [.back: 5, .biceps: 3, .lowerBack: 2, .forearms: 2]),
        ("Dumbbell Row", .dumbbell, [.back: 5, .biceps: 3, .forearms: 2]),
        ("Pull-Up", .bodyweight, [.back: 5, .biceps: 3, .forearms: 2, .core: 1]),
        ("Chin-Up", .bodyweight, [.back: 4, .biceps: 4, .forearms: 2]),
        ("Lat Pulldown", .cable, [.back: 5, .biceps: 3]),
        ("Seated Cable Row", .cable, [.back: 5, .biceps: 3, .traps: 2]),
        ("T-Bar Row", .machine, [.back: 5, .biceps: 3, .lowerBack: 2]),
        ("Straight-Arm Pulldown", .cable, [.back: 4, .triceps: 1]),
        ("Barbell Shrug", .barbell, [.traps: 5, .forearms: 2]),
        ("Back Extension", .bodyweight, [.lowerBack: 4, .glutes: 3, .hamstrings: 3]),
        // Biceps
        ("Barbell Curl", .barbell, [.biceps: 5, .forearms: 2]),
        ("Dumbbell Curl", .dumbbell, [.biceps: 5, .forearms: 2]),
        ("Hammer Curl", .dumbbell, [.biceps: 4, .forearms: 3]),
        ("Preacher Curl", .machine, [.biceps: 5]),
        ("Incline Dumbbell Curl", .dumbbell, [.biceps: 5]),
        ("Cable Curl", .cable, [.biceps: 5, .forearms: 2]),
        // Triceps
        ("Triceps Pushdown", .cable, [.triceps: 5]),
        ("Overhead Triceps Extension", .cable, [.triceps: 5]),
        ("Skull Crusher", .barbell, [.triceps: 5]),
        ("Close-Grip Bench Press", .barbell, [.triceps: 4, .chest: 3, .shoulders: 2]),
        // Quads
        ("Barbell Squat", .barbell, [.quads: 5, .glutes: 4, .lowerBack: 2, .core: 2]),
        ("Front Squat", .barbell, [.quads: 5, .glutes: 3, .core: 3]),
        ("Leg Press", .machine, [.quads: 5, .glutes: 3]),
        ("Hack Squat", .machine, [.quads: 5, .glutes: 3]),
        ("Leg Extension", .machine, [.quads: 5]),
        ("Bulgarian Split Squat", .dumbbell, [.quads: 5, .glutes: 4, .core: 1]),
        ("Walking Lunge", .dumbbell, [.quads: 4, .glutes: 4, .hamstrings: 2, .core: 1]),
        ("Goblet Squat", .dumbbell, [.quads: 4, .glutes: 3, .core: 2]),
        // Hamstrings / glutes
        ("Romanian Deadlift", .barbell, [.hamstrings: 5, .glutes: 4, .lowerBack: 3, .forearms: 2]),
        ("Lying Leg Curl", .machine, [.hamstrings: 5]),
        ("Seated Leg Curl", .machine, [.hamstrings: 5]),
        ("Hip Thrust", .barbell, [.glutes: 5, .hamstrings: 3, .quads: 1]),
        ("Glute Bridge", .bodyweight, [.glutes: 4, .hamstrings: 2]),
        ("Good Morning", .barbell, [.hamstrings: 4, .lowerBack: 4, .glutes: 3]),
        ("Cable Kickback", .cable, [.glutes: 4]),
        // Calves
        ("Standing Calf Raise", .machine, [.calves: 5]),
        ("Seated Calf Raise", .machine, [.calves: 5]),
        // Core
        ("Plank", .bodyweight, [.core: 4]),
        ("Cable Crunch", .cable, [.core: 5]),
        ("Hanging Leg Raise", .bodyweight, [.core: 5, .forearms: 1]),
        ("Ab Wheel Rollout", .bodyweight, [.core: 5, .shoulders: 1]),
    ]

    /// Built-in splits → exercise names (resolved against the catalog at start).
    static let templates: [(name: String, exercises: [String])] = [
        ("Push", ["Barbell Bench Press", "Overhead Press", "Incline Dumbbell Press",
                  "Lateral Raise", "Triceps Pushdown"]),
        ("Pull", ["Deadlift", "Barbell Row", "Lat Pulldown", "Face Pull", "Barbell Curl"]),
        ("Legs", ["Barbell Squat", "Romanian Deadlift", "Leg Press", "Lying Leg Curl",
                  "Standing Calf Raise"]),
        ("Upper", ["Barbell Bench Press", "Barbell Row", "Overhead Press",
                   "Lat Pulldown", "Barbell Curl", "Triceps Pushdown"]),
        ("Lower", ["Barbell Squat", "Romanian Deadlift", "Leg Extension",
                   "Lying Leg Curl", "Standing Calf Raise"]),
        ("Full Body Strength", ["Barbell Squat", "Barbell Bench Press", "Barbell Row"]),
    ]

    @MainActor
    static func seedIfNeeded(context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        if existing.isEmpty {
            for (name, category, tension) in catalog {
                context.insert(Exercise(name: name, category: category, tension: tension))
            }
            try? context.save()
            return
        }
        // Migrate pre-tension rows and add newly-catalogued exercises by name.
        let byName = Dictionary(grouping: existing, by: \.name)
        var changed = false
        for (name, category, tension) in catalog {
            if let row = byName[name]?.first {
                if row.tensionRaw.isEmpty {
                    row.tension = tension
                    changed = true
                }
            } else {
                context.insert(Exercise(name: name, category: category, tension: tension))
                changed = true
            }
        }
        if changed { try? context.save() }
    }
}
