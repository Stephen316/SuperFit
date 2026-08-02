import Foundation

/// How several weigh-ins on one day become that day's weight.
///
/// **The lowest reading, not the mean.**
///
/// Bodyweight climbs through the day — food and fluid put a typical adult 1–2 kg
/// above their waking figure by evening — so a day's readings are not repeated
/// samples of one quantity. They are one quantity plus however much of the day
/// had happened when each was taken.
///
/// That is what rules the mean out. Averaging makes a day's value depend on *how
/// many times somebody stepped on the scale and when*: weigh once in the morning
/// and the day reads 80.0; weigh again after dinner and the same body reads 80.6.
/// The trend is fitted across days, so an inconsistent weighing habit becomes a
/// weight change that never happened — and this engine converts weight change
/// directly into calories, at 7,700 per kilogram.
///
/// The minimum is the closest thing to the fasted, post-void reading that
/// weighing protocols ask for, and it is stable against the habit: an extra
/// evening reading cannot move it.
///
/// It is not unbiased either — the more often you weigh, the lower the minimum
/// tends to fall — but that bias is bounded by real physiology in a way the
/// mean's is not. There is a floor below which a body cannot read on a given
/// day; there is no comparable ceiling on when someone might weigh themselves.
enum DailyWeight {

    /// That day's weight, from every reading taken on it.
    static func resolve(_ readings: [Double]) -> Double? { readings.min() }

    /// One weight per calendar day, from dated readings.
    ///
    /// Takes the calendar rather than assuming one: callers differ on whether
    /// they key days by the user's calendar or a fixed gregorian one, and
    /// silently substituting either would shift day boundaries.
    static func byDay<T>(_ items: [T],
                         date: (T) -> Date,
                         weightKg: (T) -> Double?,
                         calendar: Calendar) -> [Date: Double] {
        var grouped: [Date: [Double]] = [:]
        for item in items {
            guard let kg = weightKg(item) else { continue }
            grouped[calendar.startOfDay(for: date(item)), default: []].append(kg)
        }
        return grouped.compactMapValues(resolve)
    }
}
