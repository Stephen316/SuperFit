import SwiftUI
import SwiftData

/// Builds and edits a saved meal.
///
/// The meal exists in the store from the moment it's created and every
/// ingredient persists as it's added — there is no save button to forget. That
/// also means an abandoned empty meal would linger, so one with no ingredients
/// is cleaned up on the way out.
struct MealBuilderView: View {
    /// Nil creates a new meal; passing one edits it.
    var existing: SavedMeal?
    /// Set when opened to log rather than to manage.
    var logTo: (day: Date, slot: MealSlot)?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var foods: [Food]

    @State private var meal: SavedMeal?
    @State private var name = ""
    @State private var addingIngredient = false
    @State private var pendingFood: ResolvedFood?

    private var ingredients: (resolved: [MealIngredient], missingCount: Int) {
        guard let meal else { return ([], 0) }
        let lookup = Dictionary(
            foods.map { ($0.id, (name: $0.name, brand: $0.brand,
                                 per100g: $0.resolved.per100g)) },
            uniquingKeysWith: { a, _ in a })
        return MealComposer.ingredients(
            items: meal.orderedItems.map { (id: $0.id, foodID: $0.foodID, grams: $0.servingGrams) },
            foods: lookup)
    }

    private var total: NutrientProfile { MealComposer.total(ingredients.resolved) }

    var body: some View {
        NavigationStack {
            List {
                Section("Name") {
                    TextField("e.g. Overnight oats", text: $name)
                        .onChange(of: name) { meal?.name = trimmedName; save() }
                }

                if !ingredients.resolved.isEmpty { totalsSection }
                ingredientsSection
            }
            .navigationTitle(existing == nil ? "New meal" : "Edit meal")
            .themedChrome()
            .navigationBarTitleDisplayMode(.inline)
            .featureList()
            .keyboardDoneButton()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { finish() }
                }
                .withoutGlassBackground()
                if logTo != nil && !ingredients.resolved.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Log meal") { logMeal() }.fontWeight(.semibold)
                    }
                    .withoutGlassBackground()
                }
            }
            .sheet(isPresented: $addingIngredient) {
                // The same search the diary uses — one food database, one code path.
                FoodPickerView { picked in pendingFood = picked }
            }
            .sheet(item: $pendingFood) { food in
                MealIngredientView(food: food) { grams in add(food, grams: grams) }
            }
            .task { ensureMeal() }
        }
    }

    // MARK: - Sections

    private var totalsSection: some View {
        Section {
            HStack(spacing: 0) {
                macro("Calories", total.kcal, "")
                Divider().frame(height: 34)
                macro("Protein", total.proteinG, "g")
                Divider().frame(height: 34)
                macro("Carbs", total.carbsG, "g")
                Divider().frame(height: 34)
                macro("Fat", total.fatG, "g")
            }
        } header: {
            Text("Whole meal")
        } footer: {
            if ingredients.missingCount > 0 {
                Text("\(ingredients.missingCount) ingredient\(ingredients.missingCount == 1 ? " was" : "s were") removed from your foods, so it isn't counted here.")
            }
        }
    }

    private var ingredientsSection: some View {
        Section("Ingredients") {
            ForEach(ingredients.resolved) { ingredient in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ingredient.name)
                        Text("\(Int(ingredient.servingGrams)) g · \(Int(ingredient.total.kcal)) kcal")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("P \(Int(ingredient.total.proteinG))")
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                .swipeActions {
                    Button("Remove", role: .destructive) { remove(ingredient) }
                }
            }
            Button {
                addingIngredient = true
            } label: {
                Label("Add ingredient", systemImage: "plus")
                    .font(.subheadline)
            }
        }
    }

    private func macro(_ label: String, _ value: Double, _ unit: String) -> some View {
        VStack(spacing: 3) {
            Text("\(Int(value.rounded()))\(unit)")
                .font(.headline).monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Actions

    private var trimmedName: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Untitled meal" : String(trimmed.prefix(60))
    }

    private func ensureMeal() {
        if let existing {
            meal = existing
            name = existing.name
            return
        }
        guard meal == nil else { return }
        let new = SavedMeal(name: trimmedName)
        context.insert(new)
        meal = new
        save()
    }

    private func add(_ food: ResolvedFood, grams: Double) {
        guard let meal else { return }
        // Cache first: an ingredient has to point at a stored food, and a remote
        // search hit has no row until something logs or saves it.
        let stored = FoodResolver(context: context).cache(food)
        let item = SavedMealItem(foodID: stored.id, servingGrams: grams,
                                 foodName: food.name)
        item.meal = meal
        context.insert(item)
        save()
    }

    private func remove(_ ingredient: MealIngredient) {
        guard let item = meal?.orderedItems.first(where: { $0.id == ingredient.itemID })
        else { return }
        context.delete(item)
        save()
    }

    /// Writes every ingredient into the day as its own entry rather than one
    /// combined row, so the diary keeps showing what was actually eaten and a
    /// single item can still be corrected or deleted.
    private func logMeal() {
        guard let meal, let target = logTo else { return }
        for ingredient in ingredients.resolved {
            let entry = NutritionLog(date: target.day, meal: target.slot)
            let scaled = ingredient.total
            entry.foodID = ingredient.foodID
            entry.foodName = ingredient.name
            entry.servingGrams = ingredient.servingGrams
            entry.kcal = scaled.kcal
            entry.proteinG = scaled.proteinG
            entry.carbsG = scaled.carbsG
            entry.fatG = scaled.fatG
            entry.fibreG = scaled.fibreG
            entry.micros = Dictionary(uniqueKeysWithValues: scaled.micros.compactMap { key, value in
                Micronutrient(rawValue: key).map { ($0, value) }
            })
            context.insert(entry)
        }
        meal.lastLoggedAt = .now
        save()
        dismiss()
    }

    /// An abandoned meal with nothing in it is noise in the saved list.
    private func finish() {
        if let meal, (meal.items ?? []).isEmpty, existing == nil {
            context.delete(meal)
            try? context.save()
        }
        dismiss()
    }

    private func save() { try? context.save() }
}

/// Amount picker for one ingredient, reusing the portion/gram/ounce units.
private struct MealIngredientView: View {
    let food: ResolvedFood
    let onAdd: (Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @AppStorage(UnitSystem.storageKey) private var unitsRaw = UnitSystem.metric.rawValue

    @State private var quantity: Double = 100
    @State private var unit: ServingOption = .gram

    private var units: UnitSystem { UnitSystem(rawValue: unitsRaw) ?? .metric }
    private var options: [ServingOption] { ServingOption.options(for: food) }
    private var grams: Double { quantity * unit.gramsPerUnit }

    var body: some View {
        NavigationStack {
            Form {
                Section(food.name) {
                    LabeledContent("Amount") {
                        TextField("0", value: $quantity, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    Picker("Unit", selection: $unit) {
                        ForEach(options) { Text($0.label).tag($0) }
                    }
                }
                Section("This amount") {
                    let scaled = food.scaled(grams: grams)
                    LabeledContent("Calories", value: "\(Int(scaled.kcal)) kcal")
                    LabeledContent("Protein", value: "\(Int(scaled.proteinG)) g")
                    LabeledContent("Carbs", value: "\(Int(scaled.carbsG)) g")
                    LabeledContent("Fat", value: "\(Int(scaled.fatG)) g")
                }
            }
            .navigationTitle("Add ingredient")
            .themedChrome()
            .navigationBarTitleDisplayMode(.inline)
            .featureList()
            .keyboardDoneButton()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                .withoutGlassBackground()
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add") {
                        onAdd(grams)
                        dismiss()
                    }
                    .disabled(grams <= 0 || grams > 5000)
                }
                .withoutGlassBackground()
            }
            .task {
                if let portion = options.first, portion != .gram, portion != .ounce {
                    unit = portion
                    quantity = 1
                } else if units == .imperial {
                    unit = .ounce
                    quantity = 3.5
                }
            }
        }
    }
}
