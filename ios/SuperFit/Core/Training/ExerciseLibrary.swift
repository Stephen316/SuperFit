import Foundation
import SwiftData

/// Built-in exercise catalog + workout templates. Seeded into SwiftData on
/// first launch so sets can reference stable Exercise rows.
enum ExerciseLibrary {

    static let catalog: [(String, MuscleGroup, [MuscleGroup], ExerciseCategory)] = [
        ("Barbell Bench Press", .chest, [.triceps, .shoulders], .barbell),
        ("Incline Dumbbell Press", .chest, [.triceps, .shoulders], .dumbbell),
        ("Cable Fly", .chest, [], .cable),
        ("Overhead Press", .shoulders, [.triceps], .barbell),
        ("Lateral Raise", .shoulders, [], .dumbbell),
        ("Barbell Squat", .quads, [.glutes, .core], .barbell),
        ("Leg Press", .quads, [.glutes], .machine),
        ("Leg Extension", .quads, [], .machine),
        ("Romanian Deadlift", .hamstrings, [.glutes, .back], .barbell),
        ("Leg Curl", .hamstrings, [], .machine),
        ("Deadlift", .back, [.hamstrings, .glutes, .core], .barbell),
        ("Barbell Row", .back, [.biceps], .barbell),
        ("Lat Pulldown", .back, [.biceps], .cable),
        ("Pull-Up", .back, [.biceps], .bodyweight),
        ("Seated Cable Row", .back, [.biceps], .cable),
        ("Hip Thrust", .glutes, [.hamstrings], .barbell),
        ("Bulgarian Split Squat", .quads, [.glutes], .dumbbell),
        ("Barbell Curl", .biceps, [], .barbell),
        ("Hammer Curl", .biceps, [], .dumbbell),
        ("Triceps Pushdown", .triceps, [], .cable),
        ("Overhead Triceps Extension", .triceps, [], .cable),
        ("Standing Calf Raise", .calves, [], .machine),
        ("Face Pull", .shoulders, [.back], .cable),
        ("Plank", .core, [], .bodyweight),
        ("Cable Crunch", .core, [], .cable),
    ]

    /// Named splits → exercise names (resolved against the catalog at start).
    static let templates: [(name: String, exercises: [String])] = [
        ("Push", ["Barbell Bench Press", "Overhead Press", "Incline Dumbbell Press",
                  "Lateral Raise", "Triceps Pushdown"]),
        ("Pull", ["Deadlift", "Barbell Row", "Lat Pulldown", "Face Pull", "Barbell Curl"]),
        ("Legs", ["Barbell Squat", "Romanian Deadlift", "Leg Press", "Leg Curl",
                  "Standing Calf Raise"]),
        ("Upper", ["Barbell Bench Press", "Barbell Row", "Overhead Press",
                   "Lat Pulldown", "Barbell Curl", "Triceps Pushdown"]),
        ("Lower", ["Barbell Squat", "Romanian Deadlift", "Leg Extension",
                   "Leg Curl", "Standing Calf Raise"]),
        ("Full Body Strength", ["Barbell Squat", "Barbell Bench Press", "Barbell Row"]),
    ]

    @MainActor
    static func seedIfNeeded(context: ModelContext) {
        let count = (try? context.fetchCount(FetchDescriptor<Exercise>())) ?? 0
        guard count == 0 else { return }
        for (name, primary, secondary, category) in catalog {
            let e = Exercise(name: name, primary: primary, category: category)
            e.secondaryMusclesRaw = secondary.map(\.rawValue)
            context.insert(e)
        }
        try? context.save()
    }
}

extension Exercise {
    var primaryMuscle: MuscleGroup { .init(rawValue: primaryMuscleRaw) ?? .core }
    var secondaryMuscles: [MuscleGroup] { secondaryMusclesRaw.compactMap(MuscleGroup.init) }
    var muscles: ExerciseMuscles { .init(primary: primaryMuscle, secondary: secondaryMuscles) }
}
