import SwiftUI
import SwiftData
import Charts

struct WeightView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \BodyMetrics.date, order: .reverse) private var metrics: [BodyMetrics]

    @State private var entry = ""
    @State private var syncing = false

    private var chartData: [BodyMetrics] {
        metrics.sorted { $0.date < $1.date }.suffix(90)
    }

    private var trendSlopePerWeek: Double {
        let recs = metrics.map { DailyRecord(date: $0.date, intakeKcal: nil, weightKg: $0.weightKg) }
        return MetabolismEngine()
            .estimate(records: recs, windowDays: 14,
                      prior: .init(sex: .other, ageYears: 30, heightCm: 175, activity: .moderate))
            .trendSlopeKgPerWeek
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if chartData.count >= 2 {
                        Chart {
                            ForEach(chartData) { m in
                                PointMark(x: .value("Date", m.date),
                                          y: .value("Weight", m.weightKg))
                                    .foregroundStyle(.secondary.opacity(0.4))
                                    .symbolSize(18)
                                if let t = m.trendWeightKg {
                                    LineMark(x: .value("Date", m.date),
                                             y: .value("Trend", t))
                                        .foregroundStyle(.primary)
                                        .interpolationMethod(.monotone)
                                }
                            }
                        }
                        .frame(height: 220)
                        .listRowInsets(.init(top: 12, leading: 12, bottom: 12, trailing: 12))
                    } else {
                        Text("Log a few days to see your trend.")
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    HStack {
                        Text(trendLabel).font(.subheadline)
                        Spacer()
                        Text(String(format: "%+.2f kg/wk", trendSlopePerWeek))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Log weight") {
                    HStack {
                        TextField("kg", text: $entry)
                            .keyboardType(.decimalPad)
                        Button("Add", action: addEntry)
                            .disabled(Double(entry) == nil)
                    }
                }

                Section {
                    ForEach(metrics.prefix(30)) { m in
                        HStack {
                            Text(m.date, format: .dateTime.month().day())
                            Spacer()
                            Text(String(format: "%.1f kg", m.weightKg)).monospacedDigit()
                        }
                    }
                    .onDelete(perform: delete)
                }
            }
            .navigationTitle("Weight")
            .toolbar {
                Button { Task { await syncFromHealth() } } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
                .disabled(syncing)
            }
        }
    }

    private var trendLabel: String {
        let s = trendSlopePerWeek
        if abs(s) < 0.05 { return "Weight holding steady" }
        return s < 0 ? "Losing" : "Gaining"
    }

    private func addEntry() {
        guard let kg = Double(entry) else { return }
        context.insert(BodyMetrics(date: .now, weightKg: kg, source: .manual))
        recomputeTrend()
        try? context.save()
        entry = ""
    }

    private func delete(_ offsets: IndexSet) {
        for i in offsets { context.delete(metrics[i]) }
        recomputeTrend()
        try? context.save()
    }

    /// Fill trendWeightKg with an EWMA so the chart line matches the engine.
    private func recomputeTrend() {
        let ordered = metrics.sorted { $0.date < $1.date }
        let alpha = 2.0 / (10 + 1)
        var trend: Double?
        for m in ordered {
            trend = trend.map { alpha * m.weightKg + (1 - alpha) * $0 } ?? m.weightKg
            m.trendWeightKg = trend
        }
    }

    private func syncFromHealth() async {
        syncing = true
        defer { syncing = false }
        let manager = HealthKitManager()
        guard manager.isAvailable else { return }
        let range = DateInterval(start: .now.addingTimeInterval(-365 * 86_400), end: .now)
        do {
            try await manager.requestAuthorization()
            let samples = try await manager.bodyMass(in: range)
            let existing = Set(metrics.map { Calendar.current.startOfDay(for: $0.date) })
            for s in samples {
                let day = Calendar.current.startOfDay(for: s.date)
                guard !existing.contains(day) else { continue }
                context.insert(BodyMetrics(date: s.date, weightKg: s.kg, source: .healthKit))
            }
            recomputeTrend()
            try? context.save()
        } catch {
            // Surfaced silently in Phase 1; wire to a banner in Phase 2.
        }
    }
}
