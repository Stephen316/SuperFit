import Foundation
import SwiftData

/// Reads what has been logged so reminders can stay quiet about it.
///
/// Kept apart from `ReminderService` so the scheduling rules stay pure and
/// testable; this is the only part that needs a store.
enum ReminderStateLoader {
    /// How far back to look for the quiet run. Matches the schedule's own
    /// horizon: a longer history cannot change the back-off any further.
    static let quietLookbackDays = 14

    static func load(context: ModelContext, now: Date = .now,
                     calendar: Calendar = .current) -> ReminderState {
        let today = DayBounds(now, calendar: calendar)
        let horizon = calendar.date(byAdding: .day, value: -quietLookbackDays,
                                    to: today.start) ?? today.start

        let logs = (try? context.fetch(FetchDescriptor<NutritionLog>(
            predicate: #Predicate { $0.date >= horizon }))) ?? []
        let workouts = (try? context.fetch(FetchDescriptor<WorkoutRecord>(
            predicate: #Predicate { $0.startedAt >= horizon }))) ?? []

        var state = ReminderState()
        for log in logs where log.date >= today.start && log.date < today.end {
            if let slot = MealSlot(rawValue: log.mealRaw) { state.loggedMeals.insert(slot) }
        }
        state.loggedWorkout = workouts.contains {
            $0.startedAt >= today.start && $0.startedAt < today.end
        }

        // Days with any activity at all, so a run of silence can be counted.
        var active = Set<Date>()
        for log in logs { active.insert(calendar.startOfDay(for: log.date)) }
        for workout in workouts { active.insert(calendar.startOfDay(for: workout.startedAt)) }

        // Counted from yesterday: today being empty is not yet neglect, it is
        // just early, and it must not tighten the back-off every morning.
        var quiet = 0
        for back in 1...quietLookbackDays {
            guard let day = calendar.date(byAdding: .day, value: -back, to: today.start),
                  !active.contains(day) else { break }
            quiet += 1
        }
        state.quietDays = quiet
        return state
    }
}
