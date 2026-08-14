import SwiftUI
import SwiftData
import Charts

struct DiaryView: View {
    @Environment(\.modelContext) private var context
    @AppStorage(UnitSystem.storageKey) private var unitsRaw = UnitSystem.metric.rawValue
    @Query private var profiles: [UserProfile]
    @Query private var hydrationSettings: [HydrationSettings]
    @Query private var supplements: [Supplement]
    @Query private var supplementEntries: [SupplementEntry]

    @State private var metrics: [BodyMetrics] = []
    @State private var logs: [NutritionLog] = []
    @State private var energy: [DailyEnergy] = []
    @State private var hydration: [HydrationLog] = []
    @State private var dietaryHydration: [NutritionLog] = []

    @State private var day = Calendar.current.startOfDay(for: .now)
    @State private var addingTo: MealSlot?
    @State private var showingNutrients = false
    @State private var showingSupplements = false
    @State private var showingAllergens = false
    @AppStorage(AvoidedAllergens.storageKey) private var avoidedAllergens = ""
    @State private var editingHydrationGoal = false
    @State private var addingCustomWater = false

    private var units: UnitSystem { UnitSystem(rawValue: unitsRaw) ?? .metric }

    private var dayLogs: [NutritionLog] {
        let d = DayBounds(day)
        return logs.filter { d.contains($0.date) }
            .sorted { $0.loggedAt < $1.loggedAt }
    }

    private var supplementTotal: NutrientProfile {
        SupplementIntake.total(on: day, entries: supplementEntries, supplements: supplements)
    }

    /// Food plus supplements: a protein shake counts the same either way, so the
    /// bars would understate intake if supplements were shown separately.
    private var totals: NutrientProfile {
        var t = dayLogs.reduce(into: NutrientProfile()) {
            $0.kcal += $1.kcal; $0.proteinG += $1.proteinG
            $0.carbsG += $1.carbsG; $0.fatG += $1.fatG; $0.fibreG += $1.fibreG
        }
        let s = supplementTotal
        t.kcal += s.kcal; t.proteinG += s.proteinG
        t.carbsG += s.carbsG; t.fatG += s.fatG; t.fibreG += s.fibreG
        return t
    }

    private var supplementCount: Int {
        SupplementIntake.taken(on: day, entries: supplementEntries, supplements: supplements).count
    }

    private var hydrationGoalMl: Double {
        max(hydrationSettings.first?.dailyGoalMl ?? 2_500, 250)
    }

    private var hydrationStepMl: Double {
        units == .metric ? 250 : units.storeVolume(8)
    }

    private var currentManualHydrationMl: Double {
        let bounds = DayBounds(day)
        return hydration.filter { bounds.contains($0.date) }
            .reduce(0) { $0 + $1.millilitres }
    }

    private var currentDietaryHydrationMl: Double {
        let bounds = DayBounds(day)
        return dietaryHydration.filter { bounds.contains($0.date) }
            .reduce(0) { $0 + max($1.waterMl, 0) }
    }

    private var currentHydrationMl: Double {
        currentManualHydrationMl + currentDietaryHydrationMl
    }

    private struct HydrationPoint: Identifiable {
        let date: Date
        let millilitres: Double
        var id: Date { date }
    }

    /// Seven explicit calendar days, including zeroes, so an unlogged day is a
    /// visible gap in the habit rather than silently disappearing from the graph.
    private var hydrationPoints: [HydrationPoint] {
        let cal = Calendar.current
        let end = cal.startOfDay(for: day)
        let byDay = Dictionary(hydration.map {
            (cal.startOfDay(for: $0.date), $0.millilitres)
        }, uniquingKeysWith: +)
        let dietaryByDay = Dictionary(dietaryHydration.map {
            (cal.startOfDay(for: $0.date), max($0.waterMl, 0))
        }, uniquingKeysWith: +)
        return (0..<7).reversed().compactMap { offset in
            guard let date = cal.date(byAdding: .day, value: -offset, to: end) else { return nil }
            return HydrationPoint(date: date,
                                  millilitres: (byDay[date] ?? 0) + (dietaryByDay[date] ?? 0))
        }
    }

    private var targets: MacroTargets? {
        guard let profile = profiles.first, let w = metrics.first?.basisWeightKg else { return nil }
        let recs = MetabolicRecordAssembler.dailyRecords(
            logs: logs, metrics: metrics,
            supplementKcal: SupplementIntake.dailyKcal(
                entries: supplementEntries, supplements: supplements,
                from: Date.now.addingTimeInterval(-30 * 86_400), to: .now))
        let est = MetabolismEngine().estimate(
            records: recs, windowDays: 30,
            prior: .init(sex: profile.sex, ageYears: profile.ageYears,
                         heightCm: profile.heightCm, activity: profile.activity,
                         avgActiveEnergyKcal: MetabolicRecordAssembler.avgActiveEnergy(energy: energy),
                         leanMassKg: BodyComposition.recentLeanMassKg(metrics)))
        let kcal = MetabolismEngine().calorieTarget(tdee: est, goal: profile.goal, bodyweightKg: w)
        return MacroCalculator().targets(kcal: kcal, goal: profile.goal, bodyweightKg: w,
                                         leanMassKg: BodyComposition.recentLeanMassKg(metrics))
    }

    var body: some View {
        NavigationStack {
            List {
                Group {
                    FeatureCategoryBar("Macros")
                    summarySection
                }
                .listRowBackground(Theme.surface)

                FeatureCategoryBar("Meals")
                    .listRowBackground(Theme.backgroundBase)
                    .listRowSeparator(.hidden)

                ForEach(MealSlot.allCases, id: \.self) { slot in
                    mealSection(slot)
                }
                .listRowBackground(Theme.surface)

                Group {
                    FeatureCategoryBar("Hydration")
                    hydrationSection
                    nutrientLinksSection
                }
                .listRowBackground(Theme.surface)
            }
            .navigationTitle(DayTitle.text(for: day))
            .themedChrome()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    DayStepper(day: $day)
                }
                .withoutGlassBackground()
            }
            .featureList()
            .refreshable {
                await FeatureRefresh.syncAndAggregate(context: context)
                loadDiaryData()
            }
            .stickyCategoryHeaders(["Macros", "Meals", "Hydration"])
            .settingsToolbar()
            .sheet(item: $addingTo, onDismiss: loadDiaryData) { slot in
                FoodSearchView(day: day, meal: slot)
            }
            .sheet(isPresented: $showingNutrients) { NutritionView() }
            .sheet(isPresented: $showingSupplements) { SupplementsView(day: day) }
            .sheet(isPresented: $showingAllergens) { AllergensView() }
            .fullScreenCover(isPresented: $editingHydrationGoal) {
                NumberEntrySheet(title: "Daily hydration goal", unit: units.volumeUnit,
                                 allowsDecimal: false) { updateHydrationGoal($0) }
            }
            .fullScreenCover(isPresented: $addingCustomWater) {
                NumberEntrySheet(title: "Add custom water", unit: units.volumeUnit) {
                    addCustomWater($0)
                }
            }
            .task { loadDiaryData() }
            .onChange(of: day) { _, _ in loadDiaryData() }
        }
    }

    private var summarySection: some View {
        Section {
            if let targets {
                MacroBar(label: "Calories", value: totals.kcal, target: targets.kcal, unit: "kcal")
                MacroBar(label: "Protein", value: totals.proteinG, target: targets.proteinG, unit: "g")
                MacroBar(label: "Carbs", value: totals.carbsG, target: targets.carbG, unit: "g")
                MacroBar(label: "Fat", value: totals.fatG, target: targets.fatG, unit: "g")
            } else {
                Text("Log your weight and set a goal to get targets.")
                    .font(.subheadline).foregroundStyle(Theme.textSecondary)
            }
            // The four bars are the headline; the full breakdown (fibre, sugars,
            // saturates and the micros) lives a tap away rather than in the card.
            Button {
                showingNutrients = true
            } label: {
                HStack {
                    Text("See all")
                        .font(.subheadline)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(Theme.gold)
                // A plain button hit-tests its label, and the Spacer is not part
                // of it: without this the middle of the row swallows the tap.
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("See all macros and nutrients")
        }
    }

    private var avoidedAllergenCount: Int {
        AvoidedAllergens.decode(avoidedAllergens).count
    }

    /// Detail links, parked at the end of the page: they are references rather
    /// than part of the day's logging, so they sit below the meals and water
    /// the tab exists to capture.
    private var nutrientLinksSection: some View {
        Section {
            // Presented, not pushed: this tab lives inside a paged TabView, and
            // a pushed stack would make the back-swipe fight the tab swipe.
            Button {
                showingNutrients = true
            } label: {
                Label("Vitamins and minerals", systemImage: "chart.bar.doc.horizontal")
                    .font(.subheadline)
            }
            Button {
                showingSupplements = true
            } label: {
                HStack {
                    Label("Supplements", systemImage: "pills")
                        .font(.subheadline)
                    Spacer()
                    if supplementCount > 0 {
                        Text("\(supplementCount)")
                            .font(.caption).foregroundStyle(Theme.textSecondary).monospacedDigit()
                    }
                }
            }
            Button {
                showingAllergens = true
            } label: {
                HStack {
                    Label("Allergens", systemImage: "exclamationmark.shield")
                        .font(.subheadline)
                    Spacer()
                    if avoidedAllergenCount > 0 {
                        Text("\(avoidedAllergenCount)")
                            .font(.caption).foregroundStyle(Theme.textSecondary).monospacedDigit()
                    }
                }
            }
        }
    }

    private var hydrationSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Label("Water", systemImage: "drop.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.strain)
                    Spacer()
                    Text(hydrationProgressText)
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textSecondary)
                }

                ProgressView(value: min(currentHydrationMl / hydrationGoalMl, 1))
                    .tint(Theme.strain)

                HStack(spacing: 10) {
                    hydrationButton(systemName: "minus", amountMl: -hydrationStepMl)
                        .disabled(currentManualHydrationMl <= 0)
                    hydrationButton(systemName: "plus", amountMl: hydrationStepMl)
                }

                Button { addingCustomWater = true } label: {
                    Label("Add custom amount", systemImage: "plus.circle")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.controlRadius,
                                             style: .continuous)
                                .fill(Theme.wash)
                        )
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.strain)

                if currentDietaryHydrationMl > 0 {
                    HStack {
                        Label("From logged food and drinks", systemImage: "fork.knife")
                        Spacer()
                        Text(formatHydration(currentDietaryHydrationMl))
                            .monospacedDigit()
                    }
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(.vertical, 4)

            hydrationChart

            Button {
                editingHydrationGoal = true
            } label: {
                HStack {
                    Label("Daily goal", systemImage: "target")
                    Spacer()
                    Text(formatHydration(hydrationGoalMl))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textSecondary)
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                }
                .font(.subheadline)
            }
        } footer: {
            Text("The + and − controls adjust plain water by \(formatHydration(hydrationStepMl)). Logged food and drinks also count when their water content is available.")
        }
    }

    private var hydrationChart: some View {
        let points = hydrationPoints
        let recordedTop = (points.map(\.millilitres).max() ?? 0) * 1.1
        let top = max(max(hydrationGoalMl * 1.15, recordedTop), hydrationStepMl)
        return VStack(alignment: .leading, spacing: 8) {
            Text("Last 7 days")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            Chart {
                ForEach(points) { point in
                    BarMark(x: .value("Day", point.date, unit: .day),
                            y: .value("Hydration", point.millilitres))
                        .foregroundStyle(point.millilitres >= hydrationGoalMl
                                         ? Theme.gold : Theme.strain.opacity(0.72))
                }
                RuleMark(y: .value("Daily goal", hydrationGoalMl))
                    .foregroundStyle(Theme.gold)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
            .chartYScale(domain: 0...top)
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine().foregroundStyle(Theme.divider.opacity(0.5))
                    AxisValueLabel {
                        if let millilitres = value.as(Double.self) {
                            Text(hydrationAxisLabel(millilitres))
                                .font(.caption2)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { value in
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(date, format: .dateTime.weekday(.narrow))
                                .font(.caption2)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
            }
            .frame(height: 145)
            .accessibilityLabel("Hydration over the last seven days")
        }
        .padding(.vertical, 4)
    }

    private func hydrationButton(systemName: String, amountMl: Double) -> some View {
        let adding = amountMl > 0
        return Button { adjustHydration(by: amountMl) } label: {
            Label(formatHydration(abs(amountMl)), systemImage: systemName)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                        .fill(adding ? Theme.strain.opacity(0.22) : Theme.wash)
                )
        }
        .buttonStyle(.plain)
        .foregroundStyle(adding ? Theme.strain : Theme.textSecondary)
        .accessibilityLabel("\(adding ? "Add" : "Remove") \(formatHydration(abs(amountMl)))")
    }

    private func mealSection(_ slot: MealSlot) -> some View {
        Section {
            HStack {
                Text(slot.rawValue.capitalized)
                    .font(Theme.text(15, .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                // Shares the slot's own line rather than taking a row below it:
                // four empty meals otherwise cost eight rows of nothing.
                Button {
                    addingTo = slot
                } label: {
                    Label("Add food", systemImage: "plus")
                        .font(.subheadline)
                        .foregroundStyle(Theme.gold)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add food to \(slot.rawValue)")
            }
            // Without this the separator indents to the trailing button and the
            // rule floats under "Add food" instead of spanning the row.
            .alignmentGuide(.listRowSeparatorLeading) { d in d[.leading] }
            ForEach(dayLogs.filter { $0.mealRaw == slot.rawValue }) { log in
                LogRow(log: log)
            }
            .onDelete { offsets in
                let slotLogs = dayLogs.filter { $0.mealRaw == slot.rawValue }
                for i in offsets { context.delete(slotLogs[i]) }
                try? context.save()
                loadDiaryData()
            }
        }
    }

    private var hydrationProgressText: String {
        let current = Int(units.displayVolume(currentHydrationMl).rounded())
        let goal = Int(units.displayVolume(hydrationGoalMl).rounded())
        return "\(current) / \(goal) \(units.volumeUnit)"
    }

    private func formatHydration(_ millilitres: Double) -> String {
        "\(Int(units.displayVolume(millilitres).rounded())) \(units.volumeUnit)"
    }

    private func hydrationAxisLabel(_ millilitres: Double) -> String {
        if units == .imperial {
            return "\(Int(units.displayVolume(millilitres).rounded())) oz"
        }
        if millilitres >= 1_000 {
            return String(format: "%.1f L", millilitres / 1_000)
        }
        return "\(Int(millilitres.rounded())) ml"
    }

    private func adjustHydration(by amountMl: Double) {
        let start = Calendar.current.startOfDay(for: day)
        let bounds = DayBounds(start)
        let rows = hydration.filter { bounds.contains($0.date) }
        let updatedTotal = max(0, rows.reduce(0) { $0 + $1.millilitres } + amountMl)
        if let row = rows.first {
            row.millilitres = updatedTotal
            for duplicate in rows.dropFirst() { context.delete(duplicate) }
            if updatedTotal == 0 { context.delete(row) }
        } else if amountMl > 0 {
            context.insert(HydrationLog(date: start, millilitres: updatedTotal))
        }
        try? context.save()
        loadHydrationData()
    }

    private func addCustomWater(_ displayedValue: Double?) {
        guard let displayedValue, displayedValue > 0 else { return }
        let millilitres = min(units.storeVolume(displayedValue), 10_000)
        adjustHydration(by: millilitres)
    }

    private func updateHydrationGoal(_ displayedValue: Double?) {
        guard let displayedValue, displayedValue > 0 else { return }
        let goal = min(max(units.storeVolume(displayedValue), 250), 10_000)
        let row: HydrationSettings
        if let settings = hydrationSettings.first {
            row = settings
        } else {
            row = HydrationSettings()
            context.insert(row)
        }
        row.dailyGoalMl = goal
        try? context.save()
    }

    /// The diary can navigate to any date, while target calculation only needs
    /// the current 30-day metabolism window. Fetch their union instead of every
    /// food entry and Health row ever stored.
    private func loadDiaryData() {
        let cal = Calendar.current
        let selected = DayBounds(day, calendar: cal)
        let dayStart = selected.start
        let dayEnd = selected.end
        let now = Date.now
        let metabolismStart = cal.date(byAdding: .day, value: -31, to: now) ?? now

        let logQuery = FetchDescriptor<NutritionLog>(predicate: #Predicate {
            ($0.date >= dayStart && $0.date < dayEnd)
                || ($0.date >= metabolismStart && $0.date <= now)
        })
        logs = (try? context.fetch(logQuery)) ?? []

        let metricQuery = FetchDescriptor<BodyMetrics>(
            predicate: #Predicate { $0.date >= metabolismStart && $0.date <= now },
            sortBy: [SortDescriptor(\.date, order: .reverse)])
        var loadedMetrics = (try? context.fetch(metricQuery)) ?? []
        if loadedMetrics.isEmpty {
            var latest = FetchDescriptor<BodyMetrics>(
                sortBy: [SortDescriptor(\.date, order: .reverse)])
            latest.fetchLimit = 1
            loadedMetrics = (try? context.fetch(latest)) ?? []
        }
        metrics = loadedMetrics

        let energyQuery = FetchDescriptor<DailyEnergy>(
            predicate: #Predicate { $0.date >= metabolismStart && $0.date <= now })
        energy = (try? context.fetch(energyQuery)) ?? []

        loadHydrationData()
    }

    private func loadHydrationData() {
        let cal = Calendar.current
        let end = DayBounds(day, calendar: cal).end
        let start = cal.date(byAdding: .day, value: -6,
                             to: cal.startOfDay(for: day)) ?? day
        let query = FetchDescriptor<HydrationLog>(
            predicate: #Predicate { $0.date >= start && $0.date < end },
            sortBy: [SortDescriptor(\.date)])
        hydration = (try? context.fetch(query)) ?? []

        let foodQuery = FetchDescriptor<NutritionLog>(
            predicate: #Predicate { $0.date >= start && $0.date < end && $0.waterMl > 0 },
            sortBy: [SortDescriptor(\.date)])
        dietaryHydration = (try? context.fetch(foodQuery)) ?? []
    }
}

extension MealSlot: Identifiable {
    public var id: String { rawValue }
}

struct MacroBar: View {
    let label: String
    let value: Double
    let target: Double
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.subheadline)
                Spacer()
                Text("\(Int(value)) / \(Int(target)) \(unit)")
                    .font(.caption).monospacedDigit().foregroundStyle(Theme.textSecondary)
            }
            ProgressView(value: min(value / max(target, 1), 1))
                .tint(value > target * 1.05 ? .orange : Theme.gold)
        }
        .padding(.vertical, 2)
    }
}

struct LogRow: View {
    let log: NutritionLog

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(logName).font(.subheadline)
                Text("\(Int(log.servingGrams)) g · P \(Int(log.proteinG)) · C \(Int(log.carbsG)) · F \(Int(log.fatG))")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Text("\(Int(log.kcal))").monospacedDigit()
        }
    }

    private var logName: String { log.foodName ?? "Quick add" }
}
