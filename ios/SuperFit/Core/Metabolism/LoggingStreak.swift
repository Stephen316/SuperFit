import Foundation

/// Consecutive days of keeping the model fed.
///
/// A day counts when food was logged **and** a weigh-in falls inside a rolling
/// window ending that day. Food is what the TDEE estimate consumes daily, so it
/// is required daily; weight only has to arrive often enough for the trend to
/// stay anchored, which is why it is a window rather than a daily demand.
enum LoggingStreak {
    /// Days a weigh-in stays valid for, counting the day itself. Three means
    /// weighing every third day keeps the streak: on any day D the window is
    /// D-2...D, so weigh-ins on day 1 and day 4 leave no day uncovered.
    static let weighInWindowDays = 3

    /// Bounded so a long-lived store stays cheap to scan; nobody is served
    /// differently by a 400-day streak than a 365-day one.
    static let maximumDays = 365

    /// - Parameters:
    ///   - foodDays: days with at least one food log, any time within them.
    ///   - weighDays: days with at least one body-metrics reading.
    ///   - asOf: the day to count back from, normally today.
    static func days(foodDays: Set<Date>, weighDays: Set<Date>, asOf: Date,
                     calendar: Calendar = .current) -> Int {
        let food = Set(foodDays.map(calendar.startOfDay(for:)))
        let weighed = Set(weighDays.map(calendar.startOfDay(for:)))
        guard !food.isEmpty else { return 0 }

        func qualifies(_ day: Date) -> Bool {
            guard food.contains(day) else { return false }
            // Any weigh-in from the window's first day through `day` itself.
            for back in 0..<weighInWindowDays {
                guard let d = calendar.date(byAdding: .day, value: -back, to: day) else { break }
                if weighed.contains(d) { return true }
            }
            return false
        }

        // Today failing does not break the streak: the day is not over. A count
        // that reset at midnight and only returned after breakfast would spend
        // every morning lying about the last three weeks.
        var cursor = calendar.startOfDay(for: asOf)
        if !qualifies(cursor) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor)
            else { return 0 }
            cursor = yesterday
        }

        var days = 0
        while days < maximumDays, qualifies(cursor) {
            days += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor)
            else { break }
            cursor = previous
        }
        return days
    }
}
