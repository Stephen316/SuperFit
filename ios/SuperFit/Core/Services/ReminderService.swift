import Foundation
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

    /// One-off requests allow the copy to rotate. Four reminders for 14 days
    /// stay below iOS's 64-pending-notification limit, and launch refreshes the
    /// rolling window before it runs out.
    static func plans(
        from now: Date,
        days: Int = 14,
        calendar: Calendar = .current,
        copy: ReminderCopy = .bundled
    ) -> [ReminderPlan] {
        let start = calendar.startOfDay(for: now)
        var result: [ReminderPlan] = []

        for dayOffset in 0..<days {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: start) else {
                continue
            }
            let dayNumber = calendar.ordinality(of: .day, in: .era, for: day) ?? dayOffset

            for (kindOffset, kind) in ReminderKind.allCases.enumerated() {
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

enum ReminderService {
    static func enable() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            guard granted else { return false }
            await refresh()
            return true
        } catch {
            return false
        }
    }

    static func refresh(now: Date = .now) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional else { return }

        let existing = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(ReminderSchedule.identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: existing)

        for plan in ReminderSchedule.plans(from: now) {
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
