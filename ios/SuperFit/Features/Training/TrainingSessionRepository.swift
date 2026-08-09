import Foundation
import SwiftData

/// Bounded, on-demand persistence reads used when starting a saved workout.
@MainActor
enum TrainingSessionRepository {
    static func repeatCandidates(for template: WorkoutTemplate,
                                 context: ModelContext) throws -> [TrainingSession] {
        let name = template.name
        var namedQuery = FetchDescriptor<TrainingSession>(
            predicate: #Predicate { $0.templateName == name },
            sortBy: [SortDescriptor(\TrainingSession.startedAt, order: .reverse)])
        namedQuery.fetchLimit = 50
        let named = try context.fetch(namedQuery)
        if named.contains(where: hasCompletedWork) { return named }

        // Legacy sessions predate template-name tagging. Keep the compatibility
        // fallback bounded; 250 recent sessions covers years for typical use and
        // avoids materialising an unlimited history when a template is opened.
        var legacyQuery = FetchDescriptor<TrainingSession>(
            sortBy: [SortDescriptor(\TrainingSession.startedAt, order: .reverse)])
        legacyQuery.fetchLimit = 250
        return try context.fetch(legacyQuery)
    }

    private static func hasCompletedWork(_ session: TrainingSession) -> Bool {
        (session.sets ?? []).contains { $0.completedAt != nil }
    }
}
