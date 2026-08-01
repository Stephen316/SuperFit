import SwiftUI
import SwiftData

struct FoodSearchView: View {
    let day: Date
    let meal: MealSlot

    @Environment(\.dismiss) private var dismiss

    @State private var logging: ResolvedFood?
    @State private var loggingMeal: SavedMeal?

    var body: some View {
        NavigationStack {
            FoodPickerView(showsBarcode: true, showsMeals: true,
                           onPickMeal: { loggingMeal = $0 },
                           onPick: { logging = $0 })
                .navigationTitle("Add to \(meal.rawValue.capitalized)")
                .themedChrome()
                .navigationBarTitleDisplayMode(.inline)
                .themedList()
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { dismiss() }
                    }
                    .withoutGlassBackground()
                }
                .sheet(item: $logging) { food in
                    LogFoodView(food: food, day: day, meal: meal) { dismiss() }
                }
                .sheet(item: $loggingMeal) { saved in
                    MealBuilderView(existing: saved, logTo: (day: day, slot: meal))
                }
        }
    }
}

struct LogFoodView: View {
    let food: ResolvedFood
    let day: Date
    let meal: MealSlot
    let onLogged: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var supplements: [Supplement]
    @Query private var supplementEntries: [SupplementEntry]

    @AppStorage(UnitSystem.storageKey) private var unitsRaw = UnitSystem.metric.rawValue

    @State private var resolved: ResolvedFood
    @State private var quantity: Double = 1
    @State private var unit: ServingOption = .gram
    @State private var confirmingDuplicate = false
    @State private var loadingPortions = false

    init(food: ResolvedFood, day: Date, meal: MealSlot, onLogged: @escaping () -> Void) {
        self.food = food
        self.day = day
        self.meal = meal
        self.onLogged = onLogged
        _resolved = State(initialValue: food)
    }

    private var units: UnitSystem { UnitSystem(rawValue: unitsRaw) ?? .metric }
    private var options: [ServingOption] { ServingOption.options(for: resolved) }

    /// Quantity is in the chosen unit; everything downstream works in grams.
    private var grams: Double { quantity * unit.gramsPerUnit }
    private var scaled: NutrientProfile { resolved.scaled(grams: grams) }

    /// The same product can be reached from the food diary and the supplements
    /// list, and both count toward the day's totals.
    private var alreadyTakenAsSupplement: Bool {
        SupplementIntake.isTakenAsSupplement(name: food.name, on: day,
                                             entries: supplementEntries,
                                             supplements: supplements)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent(resolved.name) {
                        if let brand = resolved.brand {
                            Text(brand).foregroundStyle(.secondary)
                        }
                    }
                    LabeledContent("Amount") {
                        TextField("0", value: $quantity, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    Picker("Unit", selection: $unit) {
                        ForEach(options) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    if unit != .gram && unit != .ounce {
                        LabeledContent("Weight", value: "\(Int(grams.rounded())) g")
                            .foregroundStyle(.secondary)
                    }
                    if loadingPortions {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text("Loading serving sizes…")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Section("This portion") {
                    LabeledContent("Calories", value: "\(Int(scaled.kcal)) kcal")
                    LabeledContent("Protein", value: "\(Int(scaled.proteinG)) g")
                    LabeledContent("Carbs", value: "\(Int(scaled.carbsG)) g")
                    LabeledContent("Fat", value: "\(Int(scaled.fatG)) g")
                    LabeledContent("Fibre", value: "\(Int(scaled.fibreG)) g")
                }
            }
            .navigationTitle("Log food")
            .themedChrome()
            .navigationBarTitleDisplayMode(.inline)
            .themedList()
            .keyboardDoneButton()
            .task { await loadPortions() }
            .alert("Already taken today", isPresented: $confirmingDuplicate) {
                Button("Log anyway") { log() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("\(food.name) is already logged in your supplements for this day. Logging it here as well will count it twice.")
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Back") { dismiss() } }
                .withoutGlassBackground()
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Log") {
                        if alreadyTakenAsSupplement {
                            confirmingDuplicate = true
                        } else {
                            log()
                        }
                    }
                    .disabled(grams <= 0 || grams > 5000)
                }
                .withoutGlassBackground()
            }
        }
    }

    /// USDA search results carry no household measures, so they're fetched when
    /// this sheet opens. Selection is only moved onto a portion if the user
    /// hasn't already chosen a unit — never yank a choice out from under them.
    private func loadPortions() async {
        applyDefaultUnit()
        guard resolved.portions.isEmpty, resolved.source == .usda else { return }
        loadingPortions = true
        defer { loadingPortions = false }
        let detailed = await FoodResolver(context: context).withPortions(resolved)
        guard !detailed.portions.isEmpty else { return }
        let wasDefault = unit == .gram || unit == .ounce
        resolved = detailed
        if wasDefault, quantity == 1 || quantity == 100 { applyDefaultUnit() }
    }

    /// Prefer a real portion; otherwise the unit that matches the user's
    /// measurement setting, with a sensible starting quantity for each.
    private func applyDefaultUnit() {
        if let portion = options.first, portion != .gram, portion != .ounce {
            unit = portion
            quantity = 1
        } else if units == .imperial {
            unit = .ounce
            quantity = 3.5
        } else {
            unit = .gram
            quantity = 100
        }
    }

    private func log() {
        let resolver = FoodResolver(context: context)
        let cached = resolver.cache(resolved)
        let entry = NutritionLog(date: day, meal: meal)
        entry.foodID = cached.id
        entry.foodName = resolved.name
        entry.servingGrams = grams
        entry.kcal = scaled.kcal
        entry.proteinG = scaled.proteinG
        entry.carbsG = scaled.carbsG
        entry.fatG = scaled.fatG
        entry.fibreG = scaled.fibreG
        entry.micros = Dictionary(uniqueKeysWithValues: scaled.micros.compactMap { key, value in
            Micronutrient(rawValue: key).map { ($0, value) }
        })
        context.insert(entry)
        try? context.save()
        dismiss()
        onLogged()
    }
}
