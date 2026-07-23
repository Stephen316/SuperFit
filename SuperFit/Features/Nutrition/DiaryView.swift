import SwiftUI
import SwiftData

struct DiaryView: View {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]
    @Query(sort: \BodyMetrics.date, order: .reverse) private var metrics: [BodyMetrics]
    @Query private var logs: [NutritionLog]
    @Query private var statuses: [DayLogStatus]

    @State private var day = Calendar.current.startOfDay(for: .now)
    @State private var addingTo: MealSlot?

    private var dayLogs: [NutritionLog] {
        logs.filter { Calendar.current.isDate($0.date, inSameDayAs: day) }
            .sorted { $0.loggedAt < $1.loggedAt }
    }

    private var dayStatus: DayLogStatus? {
        statuses.first { Calendar.current.isDate($0.date, inSameDayAs: day) }
    }

    private var totals: NutrientProfile {
        dayLogs.reduce(into: NutrientProfile()) {
            $0.kcal += $1.kcal; $0.proteinG += $1.proteinG
            $0.carbsG += $1.carbsG; $0.fatG += $1.fatG; $0.fibreG += $1.fibreG
        }
    }

    private var targets: MacroTargets? {
        guard let profile = profiles.first, let w = metrics.first?.weightKg else { return nil }
        let recs = MetabolicRecordAssembler.dailyRecords(logs: logs, metrics: metrics, statuses: statuses)
        let est = MetabolismEngine().estimate(
            records: recs, windowDays: 30,
            prior: .init(sex: profile.sex, ageYears: profile.ageYears,
                         heightCm: profile.heightCm, activity: profile.activity))
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
                completeSection
            }
            .navigationTitle(day.formatted(.dateTime.weekday(.wide).month().day()))
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                    Button { shift(1) } label: { Image(systemName: "chevron.right") }
                        .disabled(Calendar.current.isDateInToday(day))
                }
            }
            .sheet(item: $addingTo) { slot in
                FoodSearchView(day: day, meal: slot)
            }
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

    private var completeSection: some View {
        Section {
            Toggle("Logging complete for this day", isOn: Binding(
                get: { dayStatus?.loggingComplete ?? false },
                set: { newValue in
                    if let dayStatus {
                        dayStatus.loggingComplete = newValue
                    } else {
                        context.insert(DayLogStatus(date: day, loggingComplete: newValue))
                    }
                    try? context.save()
                }))
        } footer: {
            Text("Only complete days are used to estimate your energy expenditure. Mark a day complete once everything you ate is logged.")
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
