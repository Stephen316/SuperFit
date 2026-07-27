import SwiftUI
import SwiftData

struct DiaryView: View {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]
    @Query(sort: \BodyMetrics.date, order: .reverse) private var metrics: [BodyMetrics]
    @Query private var logs: [NutritionLog]
    @Query private var energy: [DailyEnergy]
    @Query private var supplements: [Supplement]
    @Query private var supplementEntries: [SupplementEntry]

    @State private var day = Calendar.current.startOfDay(for: .now)
    @State private var addingTo: MealSlot?
    @State private var showingNutrients = false
    @State private var showingSupplements = false

    private var dayLogs: [NutritionLog] {
        logs.filter { Calendar.current.isDate($0.date, inSameDayAs: day) }
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
                         leanMassKg: metrics.first?.leanMassKg))
        let kcal = MetabolismEngine().calorieTarget(tdee: est, goal: profile.goal, bodyweightKg: w)
        return MacroCalculator().targets(kcal: kcal, goal: profile.goal, bodyweightKg: w,
                                         leanMassKg: metrics.first?.leanMassKg)
    }

    var body: some View {
        NavigationStack {
            List {
                summarySection
                ForEach(MealSlot.allCases, id: \.self) { slot in
                    mealSection(slot)
                }
            }
            .navigationTitle(day.formatted(.dateTime.weekday(.wide).month().day()))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                        .accessibilityLabel("Previous day")
                    Button { shift(1) } label: { Image(systemName: "chevron.right") }
                        .disabled(Calendar.current.isDateInToday(day))
                        .accessibilityLabel("Next day")
                }
            }
            .themedList()
            .settingsToolbar()
            .sheet(item: $addingTo) { slot in
                FoodSearchView(day: day, meal: slot)
            }
            .sheet(isPresented: $showingNutrients) { NutritionView() }
            .sheet(isPresented: $showingSupplements) { SupplementsView(day: day) }
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
                    .font(.subheadline).foregroundStyle(.secondary)
            }
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
                            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
            }
        }
    }

    private func mealSection(_ slot: MealSlot) -> some View {
        Section(slot.rawValue.capitalized) {
            ForEach(dayLogs.filter { $0.mealRaw == slot.rawValue }) { log in
                LogRow(log: log)
            }
            .onDelete { offsets in
                let slotLogs = dayLogs.filter { $0.mealRaw == slot.rawValue }
                for i in offsets { context.delete(slotLogs[i]) }
                try? context.save()
            }
            Button {
                addingTo = slot
            } label: {
                Label("Add food", systemImage: "plus")
                    .font(.subheadline)
            }
        }
    }

    private func shift(_ days: Int) {
        day = Calendar.current.date(byAdding: .day, value: days, to: day) ?? day
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
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }
            ProgressView(value: min(value / max(target, 1), 1))
                .tint(value > target * 1.05 ? .orange : .primary)
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
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(Int(log.kcal))").monospacedDigit()
        }
    }

    private var logName: String { log.foodName ?? "Quick add" }
}
