import Testing
import Foundation
@testable import SuperFit

struct ReminderScheduleTests {
    private let copy = ReminderCopy.parse("""
        [morning]
        title=Start strong
        Morning one
        Morning two
        Morning three
        Morning four
        [lunch]
        title=Lunch check-in
        Lunch
        [workout]
        title=Time to move
        Workout
        [dinner]
        title=Finish well
        Dinner
        """)

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Dublin")!
        return calendar
    }

    @Test func schedulesFourPromptsAtTheRequestedTimes() throws {
        let now = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 8, hour: 7)))
        let plans = ReminderSchedule.plans(from: now, days: 1, calendar: calendar, copy: copy)

        #expect(plans.count == 4)
        #expect(plans.map { calendar.component(.hour, from: $0.date) } == [8, 14, 16, 18])
        #expect(Set(plans.map(\.identifier)).count == plans.count)
    }

    @Test func skipsTimesThatHaveAlreadyPassedToday() throws {
        let now = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 8, hour: 15)))
        let plans = ReminderSchedule.plans(from: now, days: 1, calendar: calendar, copy: copy)

        #expect(plans.map { calendar.component(.hour, from: $0.date) } == [16, 18])
    }

    @Test func copyCyclesAcrossDays() throws {
        let now = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 8, hour: 7)))
        let plans = ReminderSchedule.plans(from: now, days: 5, calendar: calendar, copy: copy)
        let morningBodies = plans.enumerated().compactMap { index, plan in
            index.isMultiple(of: ReminderKind.allCases.count) ? plan.body : nil
        }

        #expect(Set(morningBodies).count == 4)
        #expect(morningBodies.first == morningBodies.last)
    }

    @Test func parserAcceptsAnyNumberOfMessagesAndIgnoresComments() {
        let parsed = ReminderCopy.parse("""
            # This can be edited without touching Swift.
            [lunch]
            title=Lunch time
            First line
            Second line
            Third line
            """)

        #expect(parsed.sections[.lunch]?.title == "Lunch time")
        #expect(parsed.sections[.lunch]?.lines == ["First line", "Second line", "Third line"])
    }
}

/// Reminders must go quiet about what is already done, and thin out
/// rather than pepper someone who has stopped logging.
struct ReminderStateTests {
    private let cal = Calendar.current

    private let copy = ReminderCopy(sections: Dictionary(
        uniqueKeysWithValues: ReminderKind.allCases.map {
            ($0, ReminderCopy.Section(title: "T", lines: ["a", "b"]))
        }))

    /// 06:00 so every reminder hour that day is still ahead.
    private var morning: Date {
        cal.date(bySettingHour: 6, minute: 0, second: 0, of: .now)!
    }

    private func kinds(onDay offset: Int, state: ReminderState) -> Set<ReminderKind> {
        let start = cal.startOfDay(for: morning)
        let day = cal.date(byAdding: .day, value: offset, to: start)!
        return Set(ReminderSchedule.plans(from: morning, state: state,
                                          calendar: cal, copy: copy)
            .filter { cal.isDate($0.date, inSameDayAs: day) }
            .compactMap { plan in
                ReminderKind.allCases.first {
                    plan.identifier.contains(".\($0.rawValue).")
                }
            })
    }

    @Test func allFourFireWhenNothingIsLogged() {
        #expect(kinds(onDay: 0, state: ReminderState()) == Set(ReminderKind.allCases))
    }

    /// The headline ask: a logged workout silences today's workout nudge.
    @Test func aLoggedWorkoutSilencesTheWorkoutReminder() {
        let state = ReminderState(loggedWorkout: true)
        #expect(!kinds(onDay: 0, state: state).contains(.workout))
        #expect(kinds(onDay: 0, state: state).contains(.dinner))
    }

    /// And a logged lunch silences lunch only, not every meal.
    @Test func aLoggedMealSilencesOnlyThatMeal() {
        let state = ReminderState(loggedMeals: [.lunch])
        let today = kinds(onDay: 0, state: state)
        #expect(!today.contains(.lunch))
        #expect(today.contains(.morning))
        #expect(today.contains(.dinner))
    }

    /// Today's logging says nothing about tomorrow, so tomorrow stays intact.
    @Test func tomorrowIsUnaffectedByTodaysLogging() {
        let state = ReminderState(loggedMeals: [.lunch, .breakfast, .dinner],
                                  loggedWorkout: true)
        #expect(kinds(onDay: 0, state: state).isEmpty)
        #expect(kinds(onDay: 1, state: state) == Set(ReminderKind.allCases))
    }

    @Test func theScheduleThinsOutAfterQuietDays() {
        #expect(ReminderSchedule.dailyAllowance(quietDays: 0) == 4)
        #expect(ReminderSchedule.dailyAllowance(quietDays: 1) == 4)
        #expect(ReminderSchedule.dailyAllowance(quietDays: 3) == 2)
        #expect(ReminderSchedule.dailyAllowance(quietDays: 6) == 1)
    }

    /// Dinner is the one that survives — the last chance to log the day.
    @Test func dinnerIsTheLastReminderStanding() {
        #expect(kinds(onDay: 0, state: ReminderState(quietDays: 6)) == [.dinner])
    }

    /// After a week it drops to one every third day rather than going silent,
    /// which would leave no way back in.
    @Test func aWeekOfSilenceStridesButDoesNotStop() {
        let state = ReminderState(quietDays: 9)
        #expect(ReminderSchedule.dayStride(quietDays: 9) == 3)
        #expect(kinds(onDay: 0, state: state) == [.dinner])
        #expect(kinds(onDay: 1, state: state).isEmpty)
        #expect(kinds(onDay: 2, state: state).isEmpty)
        #expect(kinds(onDay: 3, state: state) == [.dinner])
    }

    @Test func nothingIsEverScheduledInThePast() {
        let plans = ReminderSchedule.plans(from: morning, state: ReminderState(),
                                           calendar: cal, copy: copy)
        #expect(plans.allSatisfy { $0.date > morning })
    }

    /// Identifiers stay unique per kind per day, or scheduling would overwrite.
    @Test func identifiersAreUnique() {
        let plans = ReminderSchedule.plans(from: morning, state: ReminderState(),
                                           calendar: cal, copy: copy)
        #expect(Set(plans.map(\.identifier)).count == plans.count)
    }
}
