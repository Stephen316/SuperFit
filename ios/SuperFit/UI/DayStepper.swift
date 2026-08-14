import SwiftUI

/// The day back/forward control: a hairline capsule split by a 1pt rule.
///
/// Shared rather than copied. It began on the dashboard and the diary drew its
/// own bare chevrons in the navigation bar, which looked like a different
/// control on a screen that steps through days the same way. One definition
/// means the two cannot drift.
///
/// Forward stops at today: there is no data ahead of now, and an empty screen
/// reads as a bug rather than as a date.
struct DayStepper: View {
    @Binding var day: Date

    private var isToday: Bool { Calendar.current.isDateInToday(day) }

    var body: some View {
        HStack(spacing: 0) {
            button("chevron.left", label: "Previous day", by: -1, enabled: true)
            Rectangle().fill(Theme.hairline).frame(width: 1, height: 16)
            button("chevron.right", label: "Next day", by: 1, enabled: !isToday)
        }
        .background(Capsule().fill(Theme.wash))
        .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
    }

    private func button(_ icon: String, label: String, by days: Int,
                        enabled: Bool) -> some View {
        Button {
            guard let moved = Calendar.current.date(byAdding: .day, value: days, to: day)
            else { return }
            withAnimation(.easeOut(duration: 0.15)) { day = moved }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(enabled ? Theme.textPrimary : Theme.textSecondary.opacity(0.4))
                .frame(width: 32, height: 26)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }
}

/// "Today" when it is, the short date otherwise — the wording both the dashboard
/// and the diary use for the day they are showing.
enum DayTitle {
    static func text(for day: Date) -> String {
        Calendar.current.isDateInToday(day) ? "Today" : formatter.string(from: day)
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEE d MMM")
        return f
    }()
}
