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
