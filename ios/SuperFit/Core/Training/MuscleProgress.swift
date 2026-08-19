import Foundation

/// Selects the completed working sets that trained one muscle.
///
/// A positive tension score means the muscle participated: 4–5 is direct work,
/// 1–3 is assisting work. Both belong in the drill-down because the weekly
/// breakdown colours and counts both; omitting assistance here would make its
/// detail page disagree with the row the user tapped.
enum MuscleProgress {
    static func affectingSets(
        _ muscle: MuscleGroup,
        records: [LiftRecord],
        tensions: [UUID: [MuscleGroup: Int]]
    ) -> [LiftRecord] {
        records
            .filter { record in
                !record.isWarmup
                    && record.reps > 0
                    && (tensions[record.exerciseID]?[muscle] ?? 0) > 0
            }
            .sorted { lhs, rhs in
                if lhs.date != rhs.date { return lhs.date > rhs.date }
                if lhs.exerciseID != rhs.exerciseID {
                    return lhs.exerciseID.uuidString < rhs.exerciseID.uuidString
                }
                return lhs.weightKg > rhs.weightKg
            }
    }

    static func tension(
        for record: LiftRecord,
        muscle: MuscleGroup,
        tensions: [UUID: [MuscleGroup: Int]]
    ) -> Int {
        tensions[record.exerciseID]?[muscle] ?? 0
    }
}
