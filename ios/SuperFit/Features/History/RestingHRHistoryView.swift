import SwiftUI
import SwiftData
import Charts

/// Resting heart rate over the last 90 days.
///
/// Fixed at 90 days rather than offering a range picker: resting HR moves slowly,
/// and the reason to look at it is the drift over months. A week of it says
/// nothing, and a year compresses the few beats that matter into a flat line.
///
/// A single day is close to meaningless here — an early alarm or a late drink
/// moves it — so the daily points are drawn faintly under a trailing mean.
struct RestingHRHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var vitals: [DailyVitals]

    static let windowDays = 90

    init() {
        let cutoff = Calendar.current.date(byAdding: .day,
                                           value: -Self.windowDays,
                                           to: .now) ?? .now
        _vitals = Query(filter: #Predicate { $0.date >= cutoff },
                        sort: \DailyVitals.date)
    }
    private var start: Date {
        Calendar.current.date(byAdding: .day, value: -Self.windowDays, to: .now) ?? .now
    }

    private var points: [HistoryPoint] {
        HistorySeries.daily(vitals.filter { $0.date >= start },
                            date: \.date, value: \.restingHR)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                FeatureBackground()
                ScrollView {
                    VStack(spacing: 14) {
                        summaryCard
                        chartCard
                        explanationCard
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Resting heart rate")
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
        let latest = all.last?.value
        let average = all.isEmpty ? nil : all.reduce(0) { $0 + $1.value } / Double(all.count)
        let change = HistorySeries.change(all)

        return HStack(spacing: 0) {
            stat("Latest", latest.map { "\(Int($0.rounded()))" } ?? "—")
            Rectangle().fill(Theme.divider).frame(width: 1, height: 44)
            stat("90-day average", average.map { "\(Int($0.rounded()))" } ?? "—")
            Rectangle().fill(Theme.divider).frame(width: 1, height: 44)
            stat("Change", change.map { String(format: "%+.1f", $0) } ?? "—")
        }
        .padding(16)
        .featurePanel()
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
            title: "Resting heart rate",
            headline: all.last.map { "\(Int($0.value)) bpm" },
            change: HistorySeries.change(all).map { String(format: "%+.1f bpm", $0) },
            // Downward is the good direction here, unlike most of the app's charts.
            changeIsGood: HistorySeries.change(all).map { $0 <= 0 },
            height: 210,
            yLabel: { "\(Int($0))" },
            content: {
                ForEach(all) { p in
                    PointMark(x: .value("Date", p.date), y: .value("bpm", p.value))
                        .foregroundStyle(Theme.textSecondary.opacity(0.45))
                        .symbolSize(14)
                }
                ForEach(mean) { p in
                    LineMark(x: .value("Date", p.date), y: .value("7-day mean", p.value))
                        .foregroundStyle(Theme.gold)
                        .interpolationMethod(.monotone)
                }
            },
            isEmpty: all.count < 2,
            emptyMessage: "Resting heart rate syncs from Apple Health. Wear your watch, including overnight, and readings will appear here."
        )
    }

    private var explanationCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Reading this")
                .font(Theme.font(15))
                .foregroundStyle(Theme.textSecondary)
            Text("A resting rate drifting down over weeks usually means aerobic fitness improving. A sustained rise is worth noticing — it tends to follow accumulated fatigue, poor sleep, illness or alcohol before it shows up anywhere else.")
                .font(Theme.font(14))
                .foregroundStyle(Theme.textPrimary)
            Text("Judge it over weeks, not days. One night out moves a single reading several beats, which is why the line is a 7-day mean and the daily readings sit behind it.")
                .font(Theme.font(13))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .featurePanel()
    }
}
