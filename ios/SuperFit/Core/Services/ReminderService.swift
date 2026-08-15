import Foundation
import SwiftData
import UserNotifications

enum ReminderSettings {
    static let enabledKey = "dailyRemindersEnabled"
}

enum ReminderKind: String, CaseIterable, Sendable {
    case morning, lunch, workout, dinner

    var hour: Int {
        switch self {
        case .morning: 8
        case .lunch: 14
        case .workout: 16
        case .dinner: 18
        }
    }

    /// The meal this reminder is about, so a logged lunch silences the lunch
    /// nudge specifically rather than every meal nudge for the day.
    var mealSlot: MealSlot? {
        switch self {
        case .morning: .breakfast
        case .lunch: .lunch
        case .dinner: .dinner
        case .workout: nil
        }
    }

    /// Order to drop reminders in as the back-off tightens. Dinner survives
    /// longest: it is the last chance to log anything for the day.
    static let priority: [ReminderKind] = [.dinner, .morning, .lunch, .workout]
}

/// What has actually been logged, so reminders can stay quiet about it.
struct ReminderState: Equatable, Sendable {
    /// Meals already logged today.
    var loggedMeals: Set<MealSlot> = []
    /// Whether a workout has been recorded today.
    var loggedWorkout = false
    /// Consecutive days before today with nothing logged at all. Drives the
    /// back-off: someone ignoring the app does not need four nudges a day.
    var quietDays = 0

    /// True when this reminder has nothing left to ask for today.
    func isSatisfied(_ kind: ReminderKind) -> Bool {
        if kind == .workout { return loggedWorkout }
        guard let slot = kind.mealSlot else { return false }
        return loggedMeals.contains(slot)
    }
}

struct ReminderCopy: Sendable {
    struct Section: Sendable {
        var title = ""
        var lines: [String] = []
    }

    var sections: [ReminderKind: Section]

    static let bundled: ReminderCopy = {
        guard let url = Bundle.main.url(forResource: "ReminderMessages", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return ReminderCopy(sections: [:])
        }
        return parse(text)
    }()

    static func parse(_ text: String) -> ReminderCopy {
        var sections: [ReminderKind: Section] = [:]
        var current: ReminderKind?

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }

            if line.hasPrefix("["), line.hasSuffix("]") {
                current = ReminderKind(rawValue: String(line.dropFirst().dropLast()))
                continue
            }
            guard let current else { continue }
            if line.hasPrefix("title=") {
                sections[current, default: Section()].title = String(line.dropFirst(6))
            } else {
                sections[current, default: Section()].lines.append(line)
            }
        }
        return ReminderCopy(sections: sections)
    }
}

struct ReminderPlan: Equatable, Sendable {
    let identifier: String
    let date: Date
    let title: String
    let body: String
}

enum ReminderSchedule {
    static let identifierPrefix = "superfit.reminder."

    /// How many reminders a day is allowed, given a run of days with nothing
    /// logged. Peppering someone who has stopped logging is how an app gets its
    /// notifications turned off for good, so the schedule thins out instead.
    ///
    /// It never reaches zero: after a week it drops to one reminder every third
    /// day, which is a way back in rather than silence.
    static func dailyAllowance(quietDays: Int) -> Int {
        switch quietDays {
        case ...1: ReminderKind.allCases.count
        case 2...3: 2
        default: 1
        }
    }

    /// Days to skip entirely once someone has been quiet for a week.
    static func dayStride(quietDays: Int) -> Int { quietDays >= 7 ? 3 : 1 }

    /// One-off requests allow the copy to rotate. Four reminders for 14 days
    /// stay below iOS's 64-pending-notification limit, and launch refreshes the
    /// rolling window before it runs out.
    ///
    /// `state` only describes today, which is all that can be known at schedule
    /// time — so today's already-logged meals are dropped here, and `refresh`
    /// is called again after each log to withdraw the rest.
    static func plans(
        from now: Date,
        days: Int = 14,
        state: ReminderState = ReminderState(),
        calendar: Calendar = .current,
        copy: ReminderCopy = .bundled
    ) -> [ReminderPlan] {
        let start = calendar.startOfDay(for: now)
        var result: [ReminderPlan] = []

        let allowance = dailyAllowance(quietDays: state.quietDays)
        let stride = dayStride(quietDays: state.quietDays)
        let allowed = Set(ReminderKind.priority.prefix(allowance))

        for dayOffset in 0..<days where dayOffset % stride == 0 {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: start) else {
                continue
            }
            let dayNumber = calendar.ordinality(of: .day, in: .era, for: day) ?? dayOffset

            for (kindOffset, kind) in ReminderKind.allCases.enumerated() {
                guard allowed.contains(kind) else { continue }
                // Only today's logging is known; later days are still open.
                if dayOffset == 0 && state.isSatisfied(kind) { continue }
                guard let section = copy.sections[kind],
                      !section.title.isEmpty,
                      !section.lines.isEmpty else { continue }
                guard let fireDate = calendar.date(bySettingHour: kind.hour,
                                                   minute: 0,
                                                   second: 0,
                                                   of: day),
                      fireDate > now else { continue }
                let line = section.lines[(dayNumber + kindOffset) % section.lines.count]
                let dayStamp = calendar.dateComponents([.year, .month, .day], from: day)
                let identifier = "\(identifierPrefix)\(kind.rawValue)."
                    + "\(dayStamp.year ?? 0)-\(dayStamp.month ?? 0)-\(dayStamp.day ?? 0)"
                result.append(ReminderPlan(identifier: identifier,
                                           date: fireDate,
                                           title: section.title,
                                           body: line))
            }
        }
        return result
    }
}

/// Serialises rescheduling.
///
/// `refresh` clears every pending request before re-adding them, so two runs
/// overlapping would let one delete what the other had just written. Chaining
/// on the previous task means only one is ever inside that window.
private actor RefreshGate {
    static let shared = RefreshGate()
    private var current: Task<Void, Never>?

    func run(_ work: @Sendable @escaping () async -> Void) async {
        let previous = current
        let task = Task {
            await previous?.value
            await work()
        }
        current = task
        await task.value
    }
}

enum ReminderService {
    /// - Parameter state: what is already logged today. Passing it matters here
    ///   as much as anywhere: enabling reminders after lunch should not then
    ///   schedule a nudge to log lunch.
    static func enable(state: ReminderState = ReminderState()) async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            guard granted else { return false }
            await refresh(state: state)
            return true
        } catch {
            return false
        }
    }

    static func refresh(now: Date = .now, state: ReminderState = ReminderState()) async {
        await RefreshGate.shared.run { await performRefresh(now: now, state: state) }
    }

    private static func performRefresh(now: Date, state: ReminderState) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional else { return }

        let existing = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(ReminderSchedule.identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: existing)

        for plan in ReminderSchedule.plans(from: now, state: state) {
            let content = UNMutableNotificationContent()
            content.title = plan.title
            content.body = plan.body
            content.sound = .default
            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: plan.date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: plan.identifier,
                                                        content: content,
                                                        trigger: trigger))
        }
    }

    static func disable() async {
        let center = UNUserNotificationCenter.current()
        let identifiers = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(ReminderSchedule.identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}
