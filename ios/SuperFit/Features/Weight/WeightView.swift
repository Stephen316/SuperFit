import SwiftUI
import SwiftData
import Charts

struct WeightView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \BodyMetrics.date, order: .reverse) private var metrics: [BodyMetrics]
    @AppStorage(UnitSystem.storageKey) private var unitsRaw = UnitSystem.metric.rawValue

    @State private var entry = ""
    @State private var syncing = false

    private var units: UnitSystem { UnitSystem(rawValue: unitsRaw) ?? .metric }

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
                                          y: .value("Weight", units.displayWeight(m.weightKg)))
                                    .foregroundStyle(.secondary.opacity(0.4))
                                    .symbolSize(18)
                                if let t = m.trendWeightKg {
                                    LineMark(x: .value("Date", m.date),
                                             y: .value("Trend", units.displayWeight(t)))
                                        .foregroundStyle(.primary)
                                        .interpolationMethod(.monotone)
                                }
                            }
                        }
                        .chartYAxis {
                            AxisMarks { value in
                                AxisGridLine()
                                AxisValueLabel {
                                    if let v = value.as(Double.self) {
                                        Text("\(Int(v)) \(units.weightUnit)")
                                    }
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
                        Text(units.weightDeltaString(trendSlopePerWeek))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Log weight") {
                    HStack {
                        TextField("Weight in \(units.weightUnit)", text: $entry)
                            .keyboardType(.decimalPad)
                        Text(units.weightUnit).foregroundStyle(.secondary)
                        Button("Add", action: addEntry)
                            .disabled(Double(entry) == nil)
                    }
                }

                Section {
                    ForEach(metrics.prefix(30)) { m in
                        HStack {
                            Text(m.date, format: .dateTime.month().day())
                            Spacer()
                            Text(units.weightString(m.weightKg)).monospacedDigit()
                        }
                    }
                    .onDelete(perform: delete)
                }
            }
            .navigationTitle("Weight")
            .navigationBarTitleDisplayMode(.inline)
            .keyboardDoneButton()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await syncFromHealth() } } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    .disabled(syncing)
                }
            }
        }
    }

    private var trendLabel: String {
        let s = trendSlopePerWeek
        if abs(s) < 0.05 { return "Weight holding steady" }
        return s < 0 ? "Losing" : "Gaining"
    }

    private func addEntry() {
        guard let value = Double(entry) else { return }
        let kg = units.storeWeight(value)
        guard (30...300).contains(kg) else { return }
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

    private func recomputeTrend() {
        AggregationService(context: context).fillWeightTrend()
    }

    private func syncFromHealth() async {
        syncing = true
        defer { syncing = false }
        await SyncCoordinator(context: context).syncAll(days: 365)
        AggregationService(context: context).runAll()
    }
}
