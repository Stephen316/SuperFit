import SwiftUI
import SwiftData
import Charts

struct WeightView: View {
    @Environment(\.modelContext) private var context
    @State private var metrics: [BodyMetrics] = []
    @AppStorage(UnitSystem.storageKey) private var unitsRaw = UnitSystem.metric.rawValue

    @State private var loggingWeight = false
    /// The row being corrected. A mistyped weigh-in skews the trend and the TDEE
    /// estimate built on it, so fixing one has to be possible without deleting
    /// and re-adding at today's date — which would move it to the wrong day.
    @State private var editing: BodyMetrics?
    @State private var editEntry = ""
    @State private var rejected: String?
    /// Swiping or tapping a row opens this; the destructive paths then confirm.
    @State private var options: BodyMetrics?
    @State private var confirmingDelete: BodyMetrics?
    @State private var confirmingEdit: PendingEdit?
    @State private var syncing = false
    @State private var storageFailure: String?

    private var units: UnitSystem { UnitSystem(rawValue: unitsRaw) ?? .metric }

    /// One point per day — the lowest reading of it, matching what every
    /// calculation uses.
    ///
    /// Plotting every reading drew the same day twice, and the higher of the two
    /// was food, fluid or clothing rather than a different weight. The list
    /// below still shows every row, because that is where a bad entry gets
    /// found and corrected.
    private var chartData: [BodyMetrics] {
        var lowest: [Date: BodyMetrics] = [:]
        for m in metrics {
            let day = Calendar.current.startOfDay(for: m.date)
            if let existing = lowest[day], existing.weightKg <= m.weightKg { continue }
            lowest[day] = m
        }
        return lowest.values.sorted { $0.date < $1.date }.suffix(90)
    }

    /// Anchoring the axis to zero makes the chart useless: 5 kg on a 100 kg body
    /// is a 5% wiggle, drawn as a flat line squashed against the top of the
    /// frame. The domain tracks the data instead.
    ///
    /// The floor is the other half of it. Without one, a fortnight of genuinely
    /// stable weight is stretched to fill the frame and 200 g of overnight water
    /// swing is drawn like a trend — the opposite error, and the worse of the
    /// two, because it invites a diet change in response to noise.
    private static let minimumSpanKg = 2.0

    private var yDomain: ClosedRange<Double> {
        var values: [Double] = []
        for m in chartData {
            values.append(m.weightKg)
            if let t = m.trendWeightKg { values.append(t) }
        }
        guard let low = values.min(), let high = values.max() else { return 0...1 }
        // 20% wider than whatever it settles on, so the lightest and heaviest
        // days aren't drawn on the frame itself.
        let span = max(high - low, Self.minimumSpanKg) * 1.2
        let centre = (high + low) / 2
        // displayWeight is a plain factor, so it converts a span as well as a
        // weight — no need to convert the bounds separately.
        return units.displayWeight(centre - span / 2)...units.displayWeight(centre + span / 2)
    }

    /// Chosen before the labels, not after: at these ranges whole numbers repeat
    /// themselves down the axis ("81, 81, 82, 82") and Charts' own spacing has
    /// no idea the duplicates are unreadable.
    private var yStep: Double {
        let span = yDomain.upperBound - yDomain.lowerBound
        let candidates: [Double] = [0.5, 1, 2, 2.5, 5, 10, 20, 25, 50]
        return candidates.first { span / $0 <= 6 } ?? 100
    }

    /// Decimals follow the step, not the value: a half-kilo step needs them to
    /// avoid repeating itself, and a 2.5 step needs them or the mark at 82.5
    /// prints as "82 kg" against a grid line that isn't 82.
    private func yLabel(_ v: Double) -> String {
        let wholeSteps = yStep == yStep.rounded()
        return String(format: "%.\(wholeSteps ? 0 : 1)f %@", v, units.weightUnit)
    }

    private var trendSlopePerWeek: Double {
        let recs = metrics.map { DailyRecord(date: $0.date, intakeKcal: nil, weightKg: $0.weightKg) }
        return MetabolismEngine()
            .estimate(records: recs, windowDays: 14,
                      prior: .init(sex: .other, ageYears: 30, heightCm: 175, activity: .moderate))
            .trendSlopeKgPerWeek
    }

    /// Pulled out of `body`: with the row alerts added, the whole view was one
    /// expression too large for the type checker to solve in its time limit.
    @ViewBuilder
    private var trendChart: some View {
                if chartData.count >= 2 {
                    Chart {
                        ForEach(chartData) { m in
                            PointMark(x: .value("Date", m.date),
                                      y: .value("Weight", units.displayWeight(m.weightKg)))
                                .foregroundStyle(Theme.textSecondary.opacity(0.7))
                                .symbolSize(18)
                            if let t = m.trendWeightKg {
                                LineMark(x: .value("Date", m.date),
                                         y: .value("Trend", units.displayWeight(t)))
                                    .foregroundStyle(Theme.gold)
                                    .interpolationMethod(.monotone)
                            }
                        }
                    }
                    .chartYScale(domain: yDomain)
                    .chartYAxis {
                        AxisMarks(values: .stride(by: yStep)) { value in
                            AxisGridLine()
                            AxisValueLabel {
                                if let v = value.as(Double.self) {
                                    Text(yLabel(v))
                                }
                            }
                        }
                    }
                    .frame(height: 220)
                    .listRowInsets(.init(top: 12, leading: 12, bottom: 12, trailing: 12))
                } else {
                    Text("Log a few days to see your trend.")
                        .foregroundStyle(Theme.textSecondary)
                }
    }

    /// The list itself, kept out of `body`: with four sections and the row
    /// action alerts stacked on top, the view was a single expression the type
    /// checker could not solve inside its time limit.
    private var entries: some View {
            List {
                Group {
                FeatureCategoryBar("Weight trend")
                Section { trendChart }

                FeatureCategoryBar("Weekly change")
                Section {
                    HStack {
                        Text(trendLabel).font(.subheadline)
                        Spacer()
                        Text(units.weightDeltaString(trendSlopePerWeek))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textSecondary)
                    }
                }

                FeatureCategoryBar("Log weight")
                Section {
                    Button { loggingWeight = true } label: {
                        HStack {
                            Text("Add a weigh-in")
                            Spacer()
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(Theme.gold)
                        }
                    }
                    .buttonStyle(.plain)
                }

                FeatureCategoryBar("Weigh-ins")
                Section {
                    ForEach(metrics.prefix(30)) { m in
                        HStack {
                            Text(m.date, format: .dateTime.month().day())
                            Spacer()
                            Text(units.weightString(m.weightKg)).monospacedDigit()
                        }
                        // Swipe only. A tap used to open the same menu, which
                        // made the row feel like a button that led somewhere and
                        // put a destructive action one stray touch away while
                        // scrolling. The footer carries the affordance instead.
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            // One button rather than separate edit and delete
                            // actions: a full-swipe delete is too easy to trigger
                            // by accident for a value the whole estimate rests on.
                            Button { options = m } label: {
                                Label("Edit or delete", systemImage: "ellipsis.circle")
                            }
                            .tint(Theme.gold)
                        }
                    }
                } footer: {
                    if !metrics.isEmpty {
                        Text("Swipe a weigh-in left to correct or remove it. A wrong "
                             + "number pulls the trend, and your calorie targets are "
                             + "built on that trend.")
                    }
                }
                }
                .listRowBackground(Theme.surface)
            }
            .refreshable { await syncFromHealth() }
            .task { loadRecentMetrics() }
    }

    var body: some View {
        NavigationStack {
            entries
            .navigationTitle("Weight")
            .themedChrome()
            .navigationBarTitleDisplayMode(.inline)
            .keyboardDoneButton()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { Task { await syncFromHealth() } } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    .disabled(syncing)
                    .accessibilityLabel("Sync with Apple Health")
                }
                .withoutGlassBackground()
            }
            .featureList()
            .stickyCategoryHeaders(["Weight trend", "Weekly change", "Log weight", "Weigh-ins"])
            .settingsToolbar()
            .confirmationDialog("Weigh-in", isPresented: Binding(
                get: { options != nil },
                set: { if !$0 { options = nil } }), presenting: options) { row in
                Button("Edit") {
                    editEntry = String(format: "%.1f", units.displayWeight(row.weightKg))
                    editing = row
                }
                Button("Delete", role: .destructive) { confirmingDelete = row }
                Button("Cancel", role: .cancel) {}
            } message: { row in
                Text(describe(row))
            }
            .alert("Correct weigh-in", isPresented: Binding(
                get: { editing != nil },
                set: { if !$0 { editing = nil } })) {
                TextField("Weight in \(units.weightUnit)", text: $editEntry)
                    .keyboardType(.decimalPad)
                Button("Continue") { stageEdit() }
                Button("Cancel", role: .cancel) { editing = nil }
            } message: {
                if let editing {
                    Text(editing.date, format: .dateTime.weekday(.wide).month().day())
                }
            }
            .alert("Change this weigh-in?", isPresented: Binding(
                get: { confirmingEdit != nil },
                set: { if !$0 { confirmingEdit = nil } }), presenting: confirmingEdit) { pending in
                Button("Change", role: .destructive) { applyEdit(pending) }
                Button("Cancel", role: .cancel) {}
            } message: { pending in
                Text(editWarning(pending))
            }
            .alert("Delete this weigh-in?", isPresented: Binding(
                get: { confirmingDelete != nil },
                set: { if !$0 { confirmingDelete = nil } }), presenting: confirmingDelete) { row in
                Button("Delete", role: .destructive) { applyDelete(row) }
                Button("Cancel", role: .cancel) {}
            } message: { row in
                Text(deleteWarning(row))
            }
            .alert("Weight out of range", isPresented: Binding(
                get: { rejected != nil },
                set: { if !$0 { rejected = nil } })) {
                Button("OK", role: .cancel) { rejected = nil }
            } message: {
                Text(rejected ?? "")
            }
            .alert("Couldn't save", isPresented: Binding(
                get: { storageFailure != nil },
                set: { if !$0 { storageFailure = nil } })) {
                Button("OK", role: .cancel) { storageFailure = nil }
            } message: {
                Text(storageFailure ?? "")
            }
            .fullScreenCover(isPresented: $loggingWeight) {
                NumberEntrySheet(title: "Weigh-in", unit: units.weightUnit,
                                 allowsDecimal: true, onCommit: addWeight)
            }
        }
    }

    private var trendLabel: String {
        let s = trendSlopePerWeek
        if abs(s) < 0.05 { return "Weight holding steady" }
        return s < 0 ? "Losing" : "Gaining"
    }

    /// Plausible human bodyweight. Anything outside is a slip — a decimal point,
    /// or pounds typed while set to kilograms.
    private static let acceptedKg = 30.0...300.0

    /// Records a weigh-in from the entry sheet. Blank is a no-op — the sheet was
    /// opened and dismissed without a number.
    private func addWeight(_ display: Double?) {
        guard let display else { return }
        let kg = units.storeWeight(display)
        guard Self.acceptedKg.contains(kg) else {
            rejected = outOfRangeMessage
            return
        }
        context.insert(BodyMetrics(date: .now, weightKg: kg, source: .manual))
        recomputeTrend()
        guard saveChanges() else { return }
        loadRecentMetrics()
    }

    private var outOfRangeMessage: String {
        let lo = units.weightString(Self.acceptedKg.lowerBound, decimals: 0)
        let hi = units.weightString(Self.acceptedKg.upperBound, decimals: 0)
        return "Enter a weight between \(lo) and \(hi)."
    }

    /// Validates the typed correction and hands it to the confirmation step.
    private func stageEdit() {
        guard let row = editing, let value = Double(editEntry) else { return }
        editing = nil
        let kg = units.storeWeight(value)
        guard Self.acceptedKg.contains(kg) else {
            rejected = outOfRangeMessage
            return
        }
        guard abs(kg - row.weightKg) > 0.001 else { return }   // nothing changed
        confirmingEdit = PendingEdit(row: row, kg: kg)
    }

    /// A correction waiting on confirmation, so the new value survives the round
    /// trip through the "are you sure" step.
    private struct PendingEdit: Identifiable {
        let row: BodyMetrics
        let kg: Double
        var id: PersistentIdentifier { row.persistentModelID }
    }

    // Built in plain functions: as inline string concatenation inside the view
    // body these tipped the type checker past its time limit.
    private static let tdeeCaveat =
        "Your calorie and macro targets are estimated from the weight trend, "
        + "so this will move your TDEE."

    private func describe(_ row: BodyMetrics) -> String {
        let day = row.date.formatted(.dateTime.weekday(.wide).month().day())
        return "\(units.weightString(row.weightKg)) on \(day)"
    }

    private func editWarning(_ pending: PendingEdit) -> String {
        let from = units.weightString(pending.row.weightKg)
        let to = units.weightString(pending.kg)
        return "\(from) becomes \(to).\n\n\(Self.tdeeCaveat)"
    }

    private func deleteWarning(_ row: BodyMetrics) -> String {
        "\(describe(row)) will be removed.\n\n\(Self.tdeeCaveat)"
    }

    private func applyEdit(_ pending: PendingEdit) {
        pending.row.weightKg = pending.kg
        // The stored trend is derived from the raw weights, so it has to be
        // rebuilt — otherwise the correction shows in the list while every
        // estimate keeps using the old number.
        recomputeTrend()
        guard saveChanges() else { return }
        loadRecentMetrics()
    }

    private func applyDelete(_ row: BodyMetrics) {
        context.delete(row)
        recomputeTrend()
        guard saveChanges() else { return }
        loadRecentMetrics()
    }

    private func recomputeTrend() {
        AggregationService(context: context).refreshWeightDerived()
    }

    private func syncFromHealth() async {
        syncing = true
        defer { syncing = false }
        let changes = await SyncCoordinator(context: context).syncAll(days: 365)
        storageFailure = changes.failureMessage
        AggregationService(context: context)
            .runAll(refreshWeightTrend: changes.weightTrendNeedsRefresh)
        loadRecentMetrics()
    }

    @discardableResult
    private func saveChanges() -> Bool {
        do {
            try context.save()
            return true
        } catch {
            storageFailure = error.localizedDescription
            return false
        }
    }

    /// Loads exactly the history this screen can display: every reading on the
    /// latest 90 distinct days. Paging to the boundary avoids materialising an
    /// unlimited weight history, while the final range fetch retains duplicate
    /// readings on the oldest displayed day so its daily-low calculation stays
    /// identical to the previous all-store query.
    private func loadRecentMetrics() {
        let calendar = Calendar.current
        let pageSize = 128
        var offset = 0
        var scanned: [BodyMetrics] = []
        var distinctDays = Set<Date>()

        while distinctDays.count < 90 {
            var page = FetchDescriptor<BodyMetrics>(
                sortBy: [SortDescriptor(\BodyMetrics.date, order: .reverse)])
            page.fetchLimit = pageSize
            page.fetchOffset = offset
            guard let rows = try? context.fetch(page), !rows.isEmpty else { break }
            scanned.append(contentsOf: rows)
            rows.forEach { distinctDays.insert(calendar.startOfDay(for: $0.date)) }
            guard rows.count == pageSize else { break }
            offset += pageSize
        }

        guard distinctDays.count >= 90,
              let oldest = distinctDays.sorted(by: >).prefix(90).last
        else {
            metrics = scanned
            return
        }

        let recent = FetchDescriptor<BodyMetrics>(
            predicate: #Predicate { $0.date >= oldest },
            sortBy: [SortDescriptor(\BodyMetrics.date, order: .reverse)])
        metrics = (try? context.fetch(recent)) ?? scanned
    }
}
