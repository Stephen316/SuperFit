import Testing
import Foundation
@testable import SuperFit

/// The rule: food every day, a weigh-in at least every third day.
struct LoggingStreakTests {
    private let cal = Calendar.current
    private let today = Calendar.current.startOfDay(for: .now)

    private func day(_ back: Int) -> Date {
        cal.date(byAdding: .day, value: -back, to: today)!
    }

    private func days(food: [Int], weigh: [Int]) -> Int {
        LoggingStreak.days(foodDays: Set(food.map(day)),
                           weighDays: Set(weigh.map(day)),
                           asOf: today, calendar: cal)
    }

    /// Weighing on days 0 and 3 leaves every day covered by a 3-day window,
    /// which is what "every third day" has to mean for the streak to survive it.
    @Test func weighingEveryThirdDayKeepsTheStreak() {
        #expect(days(food: [0, 1, 2, 3], weigh: [0, 3]) == 4)
    }

    @Test func weighingEveryDayKeepsIt() {
        #expect(days(food: [0, 1, 2], weigh: [0, 1, 2]) == 3)
    }

    /// A fourth day without a weigh-in leaves day 0 uncovered, so the streak
    /// stops there rather than counting back through the fed days.
    @Test func aFourDayGapBreaksIt() {
        #expect(days(food: [0, 1, 2, 3, 4], weigh: [4]) == 0)
    }

    /// Food is the daily requirement: a weigh-in cannot stand in for it. This is
    /// the behaviour change — the old rule counted either one.
    @Test func aWeighInAloneDoesNotCount() {
        #expect(days(food: [], weigh: [0, 1, 2]) == 0)
    }

    @Test func missingFoodInTheMiddleStopsTheCount() {
        #expect(days(food: [0, 1, 3, 4], weigh: [0, 1, 2, 3, 4]) == 2)
    }

    /// The day is not over, so nothing logged today counts back from yesterday.
    @Test func todayUnloggedDoesNotBreakIt() {
        #expect(days(food: [1, 2, 3], weigh: [1, 3]) == 3)
    }

    /// But two silent days do end it.
    @Test func yesterdayAlsoUnloggedEndsIt() {
        #expect(days(food: [2, 3, 4], weigh: [2, 4]) == 0)
    }

    @Test func noLogsAtAllIsZero() {
        #expect(days(food: [], weigh: []) == 0)
    }

    /// Time of day must not matter — a log at 23:00 belongs to that day.
    @Test func logsAreBucketedByDayNotInstant() {
        let evening = cal.date(byAdding: .hour, value: 23, to: day(1))!
        let streak = LoggingStreak.days(foodDays: [evening], weighDays: [evening],
                                        asOf: today, calendar: cal)
        #expect(streak == 1)
    }

    @Test func theCountIsBoundedToAYear() {
        let all = Array(0...400)
        #expect(days(food: all, weigh: all) == LoggingStreak.maximumDays)
    }
}
