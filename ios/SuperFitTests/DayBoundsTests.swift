import Testing
import Foundation
@testable import SuperFit

/// `DayBounds` replaced `Calendar.isDate(_:inSameDayAs:)` in every hot day
/// filter for speed, so what matters is that it still answers identically —
/// including on the two days a year that are not 24 hours long.
struct DayBoundsTests {

    private func dublin() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Dublin")!
        cal.locale = Locale(identifier: "en_IE")
        return cal
    }

    private func date(_ cal: Calendar, _ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    /// The equivalence that licenses the swap: same answer, every hour of the
    /// day, on either side of both edges.
    @Test(arguments: [
        (2026, 3, 29),   // clocks forward — a 23 hour day
        (2026, 10, 25),  // clocks back — a 25 hour day
        (2026, 6, 15),   // an ordinary 24 hour day
        (2026, 12, 31),  // year end
    ])
    func matchesTheCalendarHourByHour(y: Int, m: Int, d: Int) throws {
        let cal = dublin()
        let day = date(cal, y, m, d)
        let bounds = DayBounds(day, calendar: cal)
        let from = cal.startOfDay(for: day).addingTimeInterval(-2 * 3_600)

        for step in 0..<(29 * 4) {          // 29 hours in quarter-hour steps
            let t = from.addingTimeInterval(Double(step) * 900)
            #expect(bounds.contains(t) == cal.isDate(t, inSameDayAs: day),
                    "disagreed at \(t) on \(y)-\(m)-\(d)")
        }
    }

    /// A 25 hour day is why the end is `byAdding: .day` and not `+ 86_400`:
    /// adding a flat day would drop the last hour of entries out of it.
    @Test func aTwentyFiveHourDayHoldsTwentyFiveHours() {
        let cal = dublin()
        let day = date(cal, 2026, 10, 25)
        let bounds = DayBounds(day, calendar: cal)
        #expect(bounds.end.timeIntervalSince(bounds.start) == 25 * 3_600)
        // The hour a flat 86,400 would have excluded.
        #expect(bounds.contains(bounds.start.addingTimeInterval(24.5 * 3_600)))
    }

    @Test func aTwentyThreeHourDayHoldsTwentyThree() {
        let cal = dublin()
        let day = date(cal, 2026, 3, 29)
        let bounds = DayBounds(day, calendar: cal)
        #expect(bounds.end.timeIntervalSince(bounds.start) == 23 * 3_600)
    }

    /// Half-open, so midnight belongs to the day starting and not the one ending
    /// — otherwise an entry logged at exactly 00:00 counts twice.
    @Test func midnightBelongsToTheDayItStarts() {
        let cal = dublin()
        let day = date(cal, 2026, 6, 15)
        let bounds = DayBounds(day, calendar: cal)
        #expect(bounds.contains(bounds.start))
        #expect(!bounds.contains(bounds.end))
        #expect(DayBounds(bounds.end, calendar: cal).contains(bounds.end))
    }
}
