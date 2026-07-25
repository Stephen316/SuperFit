import SwiftUI
import SwiftData
import Charts

struct SleepView: View {
    @Query(sort: \SleepData.date, order: .reverse) private var sleep: [SleepData]
    @Query(sort: \DailyVitals.date, order: .reverse) private var vitals: [DailyVitals]

    @State private var window = 30

    private var nights: [SleepNight] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -window, to: .now) ?? .now
        return sleep.filter { $0.date >= cutoff && $0.asleepMinutes > 0 }
            .map { SleepNight(date: $0.date, asleepMinutes: $0.asleepMinutes,
                              inBedMinutes: $0.inBedMinutes, deepMinutes: $0.deepMinutes,
                              remMinutes: $0.remMinutes, coreMinutes: $0.coreMinutes,
                              bedtime: $0.bedtime, wakeTime: $0.wakeTime) }
    }

    private var summary: SleepSummary? { SleepAnalytics().summary(nights) }

    private var impact: SleepImpact? {
        let cal = Calendar.current
        var hrvByDay: [Date: Double] = [:]
        for v in vitals {
            if let hrv = v.hrvSDNN { hrvByDay[cal.startOfDay(for: v.date)] = hrv }
        }
        return SleepAnalytics().impact(nights: nights, hrvByDay: hrvByDay)
    }

    var body: some View {
        NavigationStack {
            List {
                if let summary {
                    summarySection(summary)
                    durationSection
                    if nights.contains(where: \.hasStages) { stagesSection }
                    if let impact { impactSection(impact) }
                    nightsSection
                } else {
                    emptySection
                }
            }
            .navigationTitle("Sleep")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button("Last 7 days") { window = 7 }
                        Button("Last 30 days") { window = 30 }
                        Button("Last 90 days") { window = 90 }
                    } label: {
                        Text("\(window)d").font(.subheadline)
                    }
                }
            }
            .themedList()
            .settingsToolbar()
        }
    }

    // MARK: - Sections

    private func summarySection(_ s: SleepSummary) -> some View {
        Section {
            HStack {
                stat("Average", duration(s.averageAsleepMinutes))
                Divider().frame(height: 34)
                stat("Efficiency", "\(Int(s.averageEfficiency * 100))%")
                Divider().frame(height: 34)
                if let sd = s.consistencySD {
                    stat("Consistency", "±\(Int(sd)) m")
                } else {
                    stat("Debt", duration(s.debtMinutes))
                }
            }
        } footer: {
            if s.consistencySD != nil {
                Text("Consistency is how much your bedtime varies. Under ±30 minutes is the target — a steady schedule matters as much as total hours.")
            }
        }
    }

    private var durationSection: some View {
        Section("Duration") {
            Chart {
                ForEach(nights, id: \.date) { n in
                    BarMark(x: .value("Date", n.date, unit: .day),
                            y: .value("Hours", Double(n.asleepMinutes) / 60))
                        .foregroundStyle(n.asleepMinutes >= SleepAnalytics.defaultNeedMinutes
                                         ? Theme.gold : Color.white.opacity(0.25))
                }
                RuleMark(y: .value("Need", Double(SleepAnalytics.defaultNeedMinutes) / 60))
                    .lineStyle(.init(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(.secondary)
                ForEach(SleepAnalytics().rollingAverage(nights), id: \.date) { point in
                    LineMark(x: .value("Date", point.date, unit: .day),
                             y: .value("7-day average", point.minutes / 60))
                        .foregroundStyle(.primary)
                        .interpolationMethod(.monotone)
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let v = value.as(Double.self) { Text("\(Int(v))h") }
                    }
                }
            }
            .frame(height: 180)
            .listRowInsets(.init(top: 12, leading: 12, bottom: 12, trailing: 12))
        }
    }

    private var stagesSection: some View {
        let staged = nights.filter(\.hasStages)
        let deep = staged.reduce(0) { $0 + $1.deepMinutes }
        let rem = staged.reduce(0) { $0 + $1.remMinutes }
        let core = staged.reduce(0) { $0 + $1.coreMinutes }
        let total = Double(max(1, deep + rem + core))
        return Section {
            stageRow("Deep", minutes: deep / staged.count, share: Double(deep) / total, tint: Theme.gold)
            stageRow("REM", minutes: rem / staged.count, share: Double(rem) / total, tint: Theme.gold.opacity(0.65))
            stageRow("Core", minutes: core / staged.count, share: Double(core) / total, tint: Color.white.opacity(0.35))
        } header: {
            Text("Stages — nightly average")
        } footer: {
            Text(staged.count < nights.count
                 ? "\(staged.count) of \(nights.count) nights have stage data. Stages need a watch worn overnight."
                 : "Deep sleep drives physical recovery, REM drives cognitive recovery.")
        }
    }

    private func impactSection(_ i: SleepImpact) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text(i.hrvDeltaPercent >= 0
                     ? "HRV runs \(Int(i.hrvDeltaPercent.rounded()))% higher after longer nights"
                     : "HRV runs \(Int(abs(i.hrvDeltaPercent).rounded()))% lower after longer nights")
                    .font(.subheadline.weight(.medium))
                Text("\(Int(i.longNightHRV)) ms after \(duration(Double(i.thresholdMinutes)))+ (\(i.longNights) nights) vs \(Int(i.shortNightHRV)) ms below it (\(i.shortNights) nights).")
                    .font(.caption).foregroundStyle(.secondary)
            }
        } header: {
            Text("What sleep does for you")
        } footer: {
            Text("Observed in your own data. Correlation, not proof — but it's the clearest signal available.")
        }
    }

    private var nightsSection: some View {
        Section("Nights") {
            ForEach(nights.sorted { $0.date > $1.date }.prefix(30), id: \.date) { n in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(n.date, format: .dateTime.weekday(.abbreviated).month().day())
                        if let bed = n.bedtime, let wake = n.wakeTime {
                            Text("\(bed, format: .dateTime.hour().minute()) – \(wake, format: .dateTime.hour().minute())")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(duration(Double(n.asleepMinutes))).monospacedDigit()
                        if n.inBedMinutes > 0 {
                            Text("\(Int(n.efficiency * 100))%")
                                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                }
            }
        }
    }

    private var emptySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("No sleep data yet").font(.headline)
                Text("Sleep syncs from Apple Health. Wear your watch overnight, or track sleep with your iPhone, and nights will appear here.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
        }
    }

    // MARK: - Pieces

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.title3.weight(.semibold)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func stageRow(_ name: String, minutes: Int, share: Double, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(name).font(.subheadline)
                Spacer()
                Text(duration(Double(minutes))).monospacedDigit().foregroundStyle(.secondary)
                Text("\(Int(share * 100))%")
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    .frame(width: 34, alignment: .trailing)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))
                    Capsule().fill(tint).frame(width: geo.size.width * share)
                }
            }
            .frame(height: 4)
        }
        .padding(.vertical, 2)
    }

    private func duration(_ minutes: Double) -> String {
        let total = Int(minutes.rounded())
        return total >= 60 ? "\(total / 60)h \(total % 60)m" : "\(total)m"
    }
}
