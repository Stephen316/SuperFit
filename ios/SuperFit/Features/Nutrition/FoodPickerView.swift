import SwiftUI
import SwiftData

enum FoodFilter: String, CaseIterable, Identifiable {
    case all, mine
    var id: String { rawValue }
    var label: String { self == .all ? "All" : "My foods" }
}

/// Search and choose a food. Used both to log into the diary and to add
/// ingredients to a saved meal, so there is one search surface rather than two
/// that drift apart.
struct FoodPickerView: View {
    var showsBarcode = false
    var showsMeals = false
    var onPickMeal: ((SavedMeal) -> Void)?
    let onPick: (ResolvedFood) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var storedFoods: [Food]
    @Query(sort: \SavedMeal.name) private var meals: [SavedMeal]

    @State private var query = ""
    @State private var filter = FoodFilter.all
    @State private var results: [ResolvedFood] = []
    @State private var searching = false
    @State private var scanning = false
    @State private var creatingCustom = false
    @State private var buildingMeal = false
    @State private var searchTask: Task<Void, Never>?
    @State private var confirmingDelete: ResolvedFood?

    /// Ids of everything in the user's own list — custom foods and anything
    /// previously logged. Built once per render rather than fetched per row.
    private var storedIDs: Set<String> {
        var out = Set<String>()
        for food in storedFoods {
            out.insert(food.id.uuidString)
            if let remote = food.remoteID { out.insert(remote) }
        }
        return out
    }

    private var visible: [ResolvedFood] {
        let ids = storedIDs
        return filter == .all ? results : results.filter { ids.contains($0.id) }
    }

    private var matchingMeals: [SavedMeal] {
        guard showsMeals else { return [] }
        guard !query.isEmpty else { return meals }
        return meals.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        List {
            if !matchingMeals.isEmpty && filter != .all || (showsMeals && !matchingMeals.isEmpty) {
                mealsSection
            }
            if visible.isEmpty && !searching && query.count >= 2 {
                emptyRow
            }
            ForEach(visible) { food in
                Button { onPick(food) } label: { row(food) }
                    // Swipe reveals a red bin; a full swipe removes it outright,
                    // matching the delete gesture everywhere else in iOS.
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        if storedIDs.contains(food.id) {
                            Button(role: .destructive) {
                                delete(food)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
            }
            creationRow
        }
        .searchable(text: $query, prompt: "Search foods")
        .overlay { if searching { ProgressView() } }
        .safeAreaInset(edge: .top) { filterBar }
        .onChange(of: query) { runSearch() }
        .onChange(of: filter) { if filter == .mine { runSearch() } }
        .sheet(isPresented: $scanning) { scannerSheet }
        .sheet(isPresented: $creatingCustom) {
            CustomFoodView { food in onPick(food) }
        }
        .sheet(isPresented: $buildingMeal) { MealBuilderView() }
        .toolbar {
            if showsBarcode {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { scanning = true } label: { Image(systemName: "barcode.viewfinder") }
                        .accessibilityLabel("Scan barcode")
                }
            }
        }
    }

    // MARK: - Pieces

    private var filterBar: some View {
        Picker("Filter", selection: $filter) {
            ForEach(FoodFilter.allCases) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .background(.bar)
    }

    private func row(_ food: ResolvedFood) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(food.name).foregroundStyle(.primary)
            HStack(spacing: 6) {
                if let brand = food.brand { Text(brand) }
                Text("\(Int(food.per100g.kcal)) kcal · P \(Int(food.per100g.proteinG))g per 100g")
            }
            .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var mealsSection: some View {
        Section("My meals") {
            ForEach(matchingMeals) { meal in
                Button {
                    onPickMeal?(meal)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(meal.name)
                            Text("\((meal.items ?? []).count) ingredient\((meal.items ?? []).count == 1 ? "" : "s")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        context.delete(meal)
                        try? context.save()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
    }

    private var emptyRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(filter == .mine ? "None of your foods match" : "No matches")
                .foregroundStyle(.secondary)
            if filter == .mine {
                Text("Switch to All to search the food databases, or add this as a custom food.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if !USDAClient().hasKey {
                Text("Add a USDA API key in Settings → Connected services to search the full food database.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Food search needs a connection. Foods you've logged before still work offline.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var creationRow: some View {
        Section {
            Button { creatingCustom = true } label: {
                Label("Add a food from its label", systemImage: "plus.rectangle.on.rectangle")
                    .font(.subheadline)
            }
            if showsMeals {
                Button { buildingMeal = true } label: {
                    Label("Create a meal", systemImage: "list.bullet.rectangle")
                        .font(.subheadline)
                }
            }
        }
    }

    private var scannerSheet: some View {
        NavigationStack {
            BarcodeScannerView { code in
                scanning = false
                Task {
                    searching = true
                    if let food = await FoodResolver(context: context).byBarcode(code) {
                        onPick(food)
                    }
                    searching = false
                }
            }
            .navigationTitle("Scan barcode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }

    // MARK: - Actions

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

    private func delete(_ food: ResolvedFood) {
        FoodResolver(context: context).delete(food)
        results.removeAll { $0.id == food.id }
    }
}
