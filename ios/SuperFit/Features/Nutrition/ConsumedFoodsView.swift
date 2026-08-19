import SwiftUI
import SwiftData

/// Everything eaten on one day, and what each item cost.
///
/// Reached by tapping "Calories consumed" on the dashboard, which answers "how
/// much" but not "from what". Grouped by meal in the order they're eaten rather
/// than by size, so it reads as the day rather than as a leaderboard.
struct ConsumedFoodsView: View {
    let day: Date

    @Environment(\.dismiss) private var dismiss
    @Query private var logs: [NutritionLog]

    init(day: Date) {
        self.day = day
        let bounds = DayBounds(day)
        let start = bounds.start
        let end = bounds.end
        _logs = Query(filter: #Predicate { $0.date >= start && $0.date < end },
                      sort: \NutritionLog.loggedAt)
    }

    private var dayLogs: [NutritionLog] {
        let d = DayBounds(day)
        return logs.filter { d.contains($0.date) }
    }

    private var total: Int { Int(dayLogs.reduce(0) { $0 + $1.kcal }.rounded()) }

    private func items(_ slot: MealSlot) -> [NutritionLog] {
        dayLogs.filter { $0.mealRaw == slot.rawValue }
            .sorted { $0.loggedAt < $1.loggedAt }
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEEE d MMMM")
        return f
    }()

    var body: some View {
        NavigationStack {
            ZStack {
                FeatureBackground()
                if dayLogs.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(spacing: 14) {
                            totalCard
                            ForEach(MealSlot.allCases, id: \.self) { slot in
                                let entries = items(slot)
                                if !entries.isEmpty { mealCard(slot, entries) }
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .navigationTitle("Calories consumed")
            .themedChrome()
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
                .withoutGlassBackground()
            }
        }
    }

    private var totalCard: some View {
        VStack(spacing: 4) {
            Text("\(total)")
                .font(Theme.font(38))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
            Text("kcal on \(Self.dayFormatter.string(from: day))")
                .font(Theme.font(13))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(18)
        .featurePanel()
    }

    private func mealCard(_ slot: MealSlot, _ entries: [NutritionLog]) -> some View {
        let slotKcal = Int(entries.reduce(0) { $0 + $1.kcal }.rounded())
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(slot.rawValue.capitalized)
                    .font(Theme.font(15))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text("\(slotKcal) kcal")
                    .font(Theme.font(13))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
            }
            ForEach(entries) { log in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(log.foodName ?? "Food")
                            .font(Theme.font(14))
                            .foregroundStyle(Theme.textPrimary)
                        // The portion is what makes a number checkable — 400 kcal
                        // is either right or wrong depending on how much it was.
                        Text("\(Int(log.servingGrams.rounded())) g")
                            .font(Theme.font(12))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer(minLength: 8)
                    Text("\(Int(log.kcal.rounded()))")
                        .font(Theme.font(15))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .featurePanel()
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("Nothing logged")
                .font(Theme.font(18))
                .foregroundStyle(Theme.textPrimary)
            Text("Food logged on this day will be listed here with its calories.")
                .font(Theme.font(14))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
    }
}
