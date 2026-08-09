import SwiftUI
import SwiftData

/// A day's supplements. Reached from the Diary; presented, not pushed, because
/// the tab it opens from lives inside a paged TabView.
struct SupplementsView: View {
    let day: Date

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Supplement.name) private var supplements: [Supplement]
    @Query private var entries: [SupplementEntry]

    @State private var adding = false

    private var taken: [TakenSupplement] {
        SupplementIntake.taken(on: day, entries: entries, supplements: supplements)
    }

    private var total: NutrientProfile {
        SupplementIntake.total(on: day, entries: entries, supplements: supplements)
    }

    var body: some View {
        NavigationStack {
            List {
                if taken.isEmpty {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Nothing taken").font(.headline)
                            Text("Add a supplement and mark it every day to have it carry forward automatically.")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                    }
                } else {
                    contributionSection
                    takenSection
                }

                Section {
                    Button { adding = true } label: {
                        Label("Add supplement", systemImage: "plus")
                    }
                }
            }
            .navigationTitle("Supplements")
            .themedChrome()
            .navigationBarTitleDisplayMode(.inline)
            .featureList()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
                .withoutGlassBackground()
            }
            .sheet(isPresented: $adding) {
                SupplementPickerView(day: day)
            }
        }
    }

    private var contributionSection: some View {
        Section {
            HStack {
                contribution("Calories", total.kcal, "kcal")
                contribution("Protein", total.proteinG, "g")
                contribution("Carbs", total.carbsG, "g")
                contribution("Fat", total.fatG, "g")
            }
        } header: {
            Text("Added to today")
        } footer: {
            Text(total.micros.isEmpty
                 ? "These totals are already included in your diary and nutrient targets."
                 : "Included in your diary and nutrient targets, including \(total.micros.count) micronutrients.")
        }
    }

    private var takenSection: some View {
        Section("Taken") {
            ForEach(taken) { item in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                        Text(servingText(item))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if item.isDaily {
                        Image(systemName: "repeat")
                            .font(.caption)
                            .foregroundStyle(Theme.gold)
                            .accessibilityLabel("Every day")
                    }
                }
                .swipeActions {
                    Button(item.isDaily ? "Skip today" : "Remove", role: .destructive) {
                        remove(item)
                    }
                    if item.isDaily {
                        Button("Stop") { stopDaily(item) }.tint(.orange)
                    }
                }
            }
        }
    }

    private func contribution(_ label: String, _ value: Double, _ unit: String) -> some View {
        VStack(spacing: 3) {
            Text("\(Int(value.rounded()))")
                .font(.headline).monospacedDigit()
            Text("\(label) \(unit)")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func servingText(_ item: TakenSupplement) -> String {
        let count = item.servings == item.servings.rounded()
            ? String(Int(item.servings)) : String(format: "%.1f", item.servings)
        let macro = item.total.kcal > 0 ? " · \(Int(item.total.kcal)) kcal" : ""
        return "\(count) × \(item.servingLabel)\(macro)"
    }

    /// A one-off is deleted; a daily one gets a skip for this day only, leaving
    /// the standing entry intact for tomorrow.
    private func remove(_ item: TakenSupplement) {
        if item.isDaily {
            let skip = SupplementEntry(supplementID: item.supplementID, kind: .skipped)
            skip.date = Calendar.current.startOfDay(for: day)
            context.insert(skip)
        } else if let entry = entries.first(where: { $0.id == item.id }) {
            context.delete(entry)
        }
        try? context.save()
    }

    /// Ends the routine from this day on, keeping the history before it.
    private func stopDaily(_ item: TakenSupplement) {
        guard let entry = entries.first(where: { $0.id == item.id }) else { return }
        entry.stoppedOn = Calendar.current.date(byAdding: .day, value: -1,
                                                to: Calendar.current.startOfDay(for: day))
        try? context.save()
    }
}

/// Catalog browser: pick a supplement, set servings, choose one-off or daily.
struct SupplementPickerView: View {
    let day: Date

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Supplement.name) private var supplements: [Supplement]
    @Query private var logs: [NutritionLog]

    @State private var query = ""
    @State private var selected: Supplement?
    @State private var servings = 1.0
    @State private var everyDay = false
    @State private var creatingCustom = false
    @State private var confirmingDuplicate = false

    init(day: Date) {
        self.day = day
        let bounds = DayBounds(day)
        let start = bounds.start
        let end = bounds.end
        _logs = Query(filter: #Predicate { $0.date >= start && $0.date < end })
    }

    /// Food-like supplements can be reached from the food diary too, and both
    /// count toward the day's totals.
    private var alreadyLoggedAsFood: Bool {
        guard let selected else { return false }
        return SupplementIntake.isLoggedAsFood(name: selected.name, on: day, logs: logs)
    }

    private var filtered: [Supplement] {
        query.isEmpty ? supplements
            : supplements.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let selected {
                    detail(for: selected)
                } else {
                    catalogList
                }
            }
            .navigationTitle(selected?.name ?? "Add supplement")
            .themedChrome()
            .navigationBarTitleDisplayMode(.inline)
            .featureList()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(selected == nil ? "Cancel" : "Back") {
                        if selected == nil { dismiss() } else { selected = nil }
                    }
                }
                .withoutGlassBackground()
                if selected != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Add") {
                            if alreadyLoggedAsFood {
                                confirmingDuplicate = true
                            } else {
                                add()
                            }
                        }
                        .fontWeight(.semibold)
                    }
                    .withoutGlassBackground()
                } else {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { creatingCustom = true } label: { Image(systemName: "plus") }
                            .accessibilityLabel("Create custom supplement")
                    }
                    .withoutGlassBackground()
                }
            }
            .alert("Already logged today", isPresented: $confirmingDuplicate) {
                Button("Add anyway") { add() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("\(selected?.name ?? "This") is already in your food diary for this day. Adding it here as well will count it twice.")
            }
            .sheet(isPresented: $creatingCustom) {
                CustomSupplementView { created in
                    selected = created
                }
            }
        }
    }

    private var catalogList: some View {
        List {
            ForEach(SupplementCategory.allCases, id: \.self) { category in
                let group = filtered.filter { $0.category == category }
                if !group.isEmpty {
                    Section(category.displayName) {
                        ForEach(group) { supplement in
                            Button {
                                selected = supplement
                                servings = 1
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(supplement.name).foregroundStyle(.primary)
                                    Text(summary(supplement))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .searchable(text: $query, prompt: "Search supplements")
    }

    private func detail(for supplement: Supplement) -> some View {
        Form {
            Section {
                Stepper(value: $servings, in: 0.5...20, step: 0.5) {
                    HStack {
                        Text("Servings")
                        Spacer()
                        Text("\(servings == servings.rounded() ? String(Int(servings)) : String(format: "%.1f", servings)) × \(supplement.servingLabel)")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Toggle("Every day", isOn: $everyDay)
            } footer: {
                Text(everyDay
                     ? "Carried forward automatically from today. You can skip a single day or stop it later without losing the history."
                     : "Added to this day only.")
            }

            Section("Per serving") {
                let p = supplement.perServing
                if p.kcal > 0 { row("Calories", "\(Int(p.kcal)) kcal") }
                if p.proteinG > 0 { row("Protein", "\(Int(p.proteinG)) g") }
                if p.carbsG > 0 { row("Carbs", "\(Int(p.carbsG)) g") }
                if p.fatG > 0 { row("Fat", format(p.fatG, "g")) }
                if p.fibreG > 0 { row("Fibre", format(p.fibreG, "g")) }
                ForEach(p.micros.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                    if let micro = Micronutrient(rawValue: key) {
                        row(micro.displayName, format(value, micro.unit))
                    }
                }
                if p.kcal == 0 && p.micros.isEmpty && p.proteinG == 0 {
                    Text("No calories or tracked nutrients.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).foregroundStyle(.secondary).monospacedDigit()
        }
    }

    private func format(_ v: Double, _ unit: String) -> String {
        (v == v.rounded() ? "\(Int(v))" : String(format: "%.1f", v)) + " \(unit)"
    }

    private func summary(_ supplement: Supplement) -> String {
        let p = supplement.perServing
        var parts: [String] = [supplement.servingLabel]
        if p.kcal > 0 { parts.append("\(Int(p.kcal)) kcal") }
        if p.proteinG > 0 { parts.append("P \(Int(p.proteinG)) g") }
        if !p.micros.isEmpty && p.kcal == 0 {
            parts.append("\(p.micros.count) nutrient\(p.micros.count == 1 ? "" : "s")")
        }
        return parts.joined(separator: " · ")
    }

    private func add() {
        guard let selected else { return }
        let entry = SupplementEntry(supplementID: selected.id,
                                    kind: everyDay ? .daily : .once,
                                    servings: servings)
        if everyDay {
            entry.startedOn = Calendar.current.startOfDay(for: day)
        } else {
            entry.date = Calendar.current.startOfDay(for: day)
        }
        context.insert(entry)
        try? context.save()
        dismiss()
    }
}

struct CustomSupplementView: View {
    let onCreated: (Supplement) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var category = SupplementCategory.health
    @State private var servingLabel = "capsule"
    @State private var kcal = 0.0
    @State private var protein = 0.0
    @State private var carbs = 0.0
    @State private var fat = 0.0
    @State private var micros: [Micronutrient: Double] = [:]

    private var isValid: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty && trimmed.count <= 60
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    TextField("Serving (e.g. capsule, 5 g)", text: $servingLabel)
                    Picker("Category", selection: $category) {
                        ForEach(SupplementCategory.allCases, id: \.self) {
                            Text($0.displayName).tag($0)
                        }
                    }
                }
                Section("Per serving") {
                    numberRow("Calories", $kcal, "kcal")
                    numberRow("Protein", $protein, "g")
                    numberRow("Carbs", $carbs, "g")
                    numberRow("Fat", $fat, "g")
                }
                Section {
                    ForEach(Micronutrient.allCases, id: \.self) { micro in
                        numberRow(micro.displayName,
                                  Binding(get: { micros[micro] ?? 0 },
                                          set: { micros[micro] = $0 > 0 ? $0 : nil }),
                                  micro.unit)
                    }
                } header: {
                    Text("Micronutrients")
                } footer: {
                    Text("Leave at zero for anything the label doesn't list.")
                }
            }
            .navigationTitle("Custom supplement")
            .themedChrome()
            .navigationBarTitleDisplayMode(.inline)
            .featureList()
            .keyboardDoneButton()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                .withoutGlassBackground()
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }.disabled(!isValid)
                }
                .withoutGlassBackground()
            }
        }
    }

    private func numberRow(_ label: String, _ value: Binding<Double>, _ unit: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
            Text(unit).foregroundStyle(.secondary).frame(width: 34, alignment: .leading)
        }
    }

    private func save() {
        let profile = NutrientProfile(
            kcal: kcal, proteinG: protein, carbsG: carbs, fatG: fat, fibreG: 0,
            micros: Dictionary(uniqueKeysWithValues:
                micros.filter { $0.value > 0 }.map { ($0.key.rawValue, $0.value) }))
        let supplement = Supplement(name: name.trimmingCharacters(in: .whitespaces),
                                    category: category,
                                    servingLabel: servingLabel.isEmpty ? "serving" : servingLabel,
                                    profile: profile,
                                    isCustom: true)
        context.insert(supplement)
        try? context.save()
        dismiss()
        onCreated(supplement)
    }
}
