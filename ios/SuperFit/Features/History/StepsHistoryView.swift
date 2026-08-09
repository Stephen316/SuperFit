import SwiftUI
import SwiftData
import Charts

/// Daily step count over time.
///
/// Steps are the one activity measure that accumulates without being a workout,
/// so the shape that matters is day-to-day consistency rather than any single
/// figure — hence bars per day with a trailing mean laid over them.
struct StepsHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var energy: [DailyEnergy]

    @State private var range = HistoryRange.quarter

    init() {
        let cutoff = HistoryRange.year.start
        _energy = Query(filter: #Predicate { $0.date >= cutoff },
                        sort: \DailyEnergy.date)
    }

    private var points: [HistoryPoint] {
        energy.filter { $0.date >= range.start && $0.steps > 0 }
            .map { HistoryPoint(date: $0.date, value: Double($0.steps)) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                FeatureBackground()
                ScrollView {
                    VStack(spacing: 14) {
                        FeatureTabControl(
                            options: HistoryRange.allCases.map { ($0, $0.label) },
                            selection: $range)

                        summaryCard
                        chartCard
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Steps")
            .themedChrome()
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
                .withoutGlassBackground()
            }
        }
    }

    private var summaryCard: some View {
        let all = points
        let average = all.isEmpty ? nil : all.reduce(0) { $0 + $1.value } / Double(all.count)
        let best = all.map(\.value).max()
        let total = all.reduce(0) { $0 + $1.value }

        return HStack(spacing: 0) {
            stat("Daily average", average.map { "\(Int($0.rounded()))" } ?? "—")
            Rectangle().fill(Theme.divider).frame(width: 1, height: 44)
            stat("Best day", best.map { "\(Int($0))" } ?? "—")
            Rectangle().fill(Theme.divider).frame(width: 1, height: 44)
            stat("Total", all.isEmpty ? "—" : compact(total))
        }
        .padding(16)
        .featurePanel()
    }

    /// Step totals run to six figures over a quarter, which doesn't fit the
    /// column — 1.2M reads better than 1,243,905 and loses nothing here.
    private func compact(_ value: Double) -> String {
        switch value {
        case 1_000_000...: return String(format: "%.1fM", value / 1_000_000)
        case 10_000...:    return String(format: "%.0fk", value / 1_000)
        default:           return "\(Int(value))"
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(Theme.font(22))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
            Text(label)
                .font(Theme.font(12))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var chartCard: some View {
        let all = points
        let mean = HistorySeries.rollingMean(all)
        return HistoryChartCard(
            title: "Steps per day",
            headline: all.last.map { "\(Int($0.value)) today" },
            height: 200,
            yLabel: { $0 >= 1000 ? "\(Int($0 / 1000))k" : "\(Int($0))" },
            content: {
                ForEach(all) { p in
                    BarMark(x: .value("Date", p.date, unit: .day),
                            y: .value("Steps", p.value))
                        .foregroundStyle(Theme.gold.opacity(0.55))
                }
                // The mean is what shows whether the habit is holding; single
                // days swing too much to read a direction from.
                ForEach(mean) { p in
                    LineMark(x: .value("Date", p.date), y: .value("7-day mean", p.value))
                        .foregroundStyle(Theme.textPrimary)
                        .interpolationMethod(.monotone)
                }
            },
            isEmpty: all.count < 2,
            emptyMessage: "Steps sync from Apple Health. Carry your phone or wear your watch and days will appear here."
        )
    }
}
