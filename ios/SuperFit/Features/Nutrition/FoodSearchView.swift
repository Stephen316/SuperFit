import SwiftUI
import SwiftData

struct FoodSearchView: View {
    let day: Date
    let meal: MealSlot

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var results: [ResolvedFood] = []
    @State private var searching = false
    @State private var scanning = false
    @State private var creatingCustom = false
    @State private var logging: ResolvedFood?
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            List {
                if results.isEmpty && !searching && query.count >= 2 {
                    Text("No matches. Try the barcode scanner or add a custom food.")
                        .foregroundStyle(.secondary)
                }
                ForEach(results) { food in
                    Button { logging = food } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(food.name).foregroundStyle(.primary)
                            HStack(spacing: 6) {
                                if let brand = food.brand { Text(brand) }
                                Text("\(Int(food.per100g.kcal)) kcal · P \(Int(food.per100g.proteinG))g per 100g")
                            }
                            .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: "Search foods")
            .overlay { if searching { ProgressView() } }
            .navigationTitle("Add to \(meal.rawValue.capitalized)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { scanning = true } label: { Image(systemName: "barcode.viewfinder") }
                    Button { creatingCustom = true } label: { Image(systemName: "plus") }
                }
            }
            .onChange(of: query) { runSearch() }
            .sheet(isPresented: $scanning) { scannerSheet }
            .sheet(isPresented: $creatingCustom) {
                CustomFoodView { food in
                    logging = food
                }
            }
            .sheet(item: $logging) { food in
                LogFoodView(food: food, day: day, meal: meal) { dismiss() }
            }
        }
    }

    private var scannerSheet: some View {
        NavigationStack {
            BarcodeScannerView { code in
                scanning = false
                Task {
                    searching = true
                    logging = await FoodResolver(context: context).byBarcode(code)
                    searching = false
                }
            }
            .navigationTitle("Scan barcode")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func runSearch() {
        searchTask?.cancel()
        let term = query
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(400))   // debounce
            guard !Task.isCancelled else { return }
            searching = true
            results = await FoodResolver(context: context).search(term)
            searching = false
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
    @State private var grams: Double = 100

    private var scaled: NutrientProfile { food.scaled(grams: grams) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent(food.name) {
                        if let brand = food.brand {
                            Text(brand).foregroundStyle(.secondary)
                        }
                    }
                    LabeledContent("Amount") {
                        TextField("g", value: $grams, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    if let serving = food.servingGrams {
                        Button("Use 1 serving (\(Int(serving)) g)") { grams = serving }
                            .font(.subheadline)
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Back") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Log") { log() }.disabled(grams <= 0 || grams > 5000)
                }
            }
        }
    }

    private func log() {
        let resolver = FoodResolver(context: context)
        let cached = resolver.cache(food)
        let entry = NutritionLog(date: day, meal: meal)
        entry.foodID = cached.id
        entry.foodName = food.name
        entry.servingGrams = grams
        entry.kcal = scaled.kcal
        entry.proteinG = scaled.proteinG
        entry.carbsG = scaled.carbsG
        entry.fatG = scaled.fatG
        entry.fibreG = scaled.fibreG
        context.insert(entry)
        try? context.save()
        dismiss()
        onLogged()
    }
}
