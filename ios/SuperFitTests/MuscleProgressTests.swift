import Foundation
import Testing
@testable import SuperFit

struct MuscleProgressTests {
    private let bench = UUID()
    private let pushdown = UUID()
    private let squat = UUID()

    private var tensions: [UUID: [MuscleGroup: Int]] {
        [
            bench: [.chest: 5, .tricepsLateral: 3],
            pushdown: [.tricepsLateral: 5],
            squat: [.vastusLateralis: 5],
        ]
    }

    private func set(_ exercise: UUID, daysAgo: Int, weight: Double = 50,
                     reps: Int = 8, warmup: Bool = false) -> LiftRecord {
        LiftRecord(date: Date.now.addingTimeInterval(-Double(daysAgo) * 86_400),
                   exerciseID: exercise, weightKg: weight, reps: reps,
                   isWarmup: warmup)
    }

    @Test("Muscle history includes direct and assisting work only")
    func directAndSecondarySets() {
        let result = MuscleProgress.affectingSets(.tricepsLateral, records: [
            set(bench, daysAgo: 2),
            set(pushdown, daysAgo: 1),
            set(squat, daysAgo: 0),
        ], tensions: tensions)

        #expect(result.map(\.exerciseID) == [pushdown, bench])
        #expect(MuscleProgress.tension(for: result[0], muscle: .tricepsLateral,
                                      tensions: tensions) == 5)
        #expect(MuscleProgress.tension(for: result[1], muscle: .tricepsLateral,
                                      tensions: tensions) == 3)
    }

    @Test("Warm-ups and zero-rep entries never appear as affecting sets")
    func excludesUnperformedWork() {
        let result = MuscleProgress.affectingSets(.tricepsLateral, records: [
            set(pushdown, daysAgo: 0, warmup: true),
            set(pushdown, daysAgo: 0, reps: 0),
            set(pushdown, daysAgo: 1, reps: 10),
        ], tensions: tensions)

        #expect(result.count == 1)
        #expect(result.first?.reps == 10)
    }
}
