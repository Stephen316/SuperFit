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
    @State private var hasMore = false
    @State private var loadingMore = false
    @State private var loadedPage = 1
    @State private var store: StoreBrand?
    @AppStorage(FoodRegionSetting.storageKey) private var foodRegionRaw = FoodRegionSetting.automatic

    /// The chosen country drives both the search ranking and which retailers the
    /// chips offer, so changing it in Settings moves both together.
    private var region: FoodRegion? {
        FoodRegionSetting.effective(stored: foodRegionRaw)
    }

    private var stores: [StoreBrand] { StoreBrand.forRegion(region?.code) }

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

    /// A run of results under one heading. A nil title means a plain ungrouped
    /// list, which is what a store browse or a single-category result should be.
    private struct FoodSection: Identifiable {
        let title: String?
        let foods: [ResolvedFood]
        var id: String { title ?? "" }
    }

    /// Splits the results into the food that was asked for and everything else
    /// merely named after it.
    ///
    /// Ordering already puts rice above rice cakes, but a heading is what makes
    /// that legible: the complaint was that searching "rice" showed rice cakes and
    /// Rice Krispies with no actual rice in sight, and a reordered but unlabelled
    /// list still leaves you scanning for where one group ends.
    private var sections: [FoodSection] {
        let foods = visible
        let term = query.trimmingCharacters(in: .whitespaces)
        guard term.count >= FoodSearch.minimumQueryLength else {
            return [FoodSection(title: nil, foods: foods)]
        }

        // Partitioned, not re-ranked. The resolver has already ordered these, and
        // ranking again here would silently disagree with it — this view doesn't
        // know which foods were eaten recently, so its idea of the order is worse.
        var isTheFood: [ResolvedFood] = []
        var namedAfterIt: [ResolvedFood] = []
        for food in foods {
            let match = FoodNameMatch.match(name: food.name, brand: food.brand,
                                            query: term)
            if match <= .headNounAnyOrder { isTheFood.append(food) }
            else { namedAfterIt.append(food) }
        }

        // A heading with nothing to contrast against is just noise.
        guard !isTheFood.isEmpty, !namedAfterIt.isEmpty else {
            return [FoodSection(title: nil, foods: foods)]
        }
        return [FoodSection(title: term.capitalized, foods: isTheFood),
                FoodSection(title: "Other matches", foods: namedAfterIt)]
    }

    /// Hoists `storedIDs` out of the row loop: it walks every stored food to build
    /// a set, and reading it per row rebuilt that set once per result.
    @ViewBuilder
    private func foodRows(_ foods: [ResolvedFood]) -> some View {
        let ids = storedIDs
        ForEach(foods) { food in
            Button { onPick(food) } label: { row(food) }
                // Swipe reveals a red bin; a full swipe removes it outright,
                // matching the delete gesture everywhere else in iOS.
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    if ids.contains(food.id) {
                        Button(role: .destructive) {
                            delete(food)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
        }
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
            if visible.isEmpty && !searching && query.count >= FoodSearch.minimumQueryLength {
                emptyRow
            }
            let sections = sections
            if sections.count == 1 {
                foodRows(sections[0].foods)
            } else {
                ForEach(sections) { section in
                    Section(section.title ?? "") { foodRows(section.foods) }
                }
            }
            if hasMore && filter == .all && !visible.isEmpty {
                loadMoreRow
            }
            creationRow
        }
        .searchable(text: $query, prompt: "Search foods")
        .overlay { if searching { ProgressView() } }
        .safeAreaInset(edge: .top) { filterBar }
        .onChange(of: query) { runSearch() }
        .onChange(of: filter) { if filter == .mine { runSearch() } }
        .onChange(of: foodRegionRaw) {
            // A chip for a retailer that doesn't operate in the new country would
            // otherwise stay selected and silently return nothing.
            if let store, !stores.contains(store) { self.store = nil }
            runSearch()
        }
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
        VStack(spacing: 8) {
            Picker("Filter", selection: $filter) {
                ForEach(FoodFilter.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)

            if filter == .all && !stores.isEmpty { storeBar }
        }
        .padding(.bottom, 8)
        .background(.bar)
    }

    /// Own-brand filters for the local retailers.
    ///
    /// Labelled "own brand" rather than "sold at" because that's what it is:
    /// Open Food Facts indexes who made a product, and its stocked-in field
    /// returns nothing. This finds Tesco Finest pasta, not a jar of Hellmann's
    /// bought in Tesco, and the label shouldn't promise the second.
    private var storeBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(stores) { brand in
                    let selected = store == brand
                    Button {
                        store = selected ? nil : brand
                        runSearch()
                    } label: {
                        Text(brand.displayName)
                            .font(.caption.weight(selected ? .semibold : .regular))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(selected ? Theme.gold.opacity(0.25) : .clear)
                                    .overlay(Capsule().stroke(
                                        selected ? Theme.gold : Theme.hairline.opacity(0.4),
                                        lineWidth: 1)))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(selected ? Theme.gold : .secondary)
                }
            }
            .padding(.horizontal, 16)
        }
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

    private var loadMoreRow: some View {
        Button(action: loadMore) {
            HStack {
                Spacer()
                if loadingMore {
                    ProgressView()
                } else {
                    Text("Load more results")
                        .font(.subheadline)
                        .foregroundStyle(Theme.gold)
                }
                Spacer()
            }
        }
        .disabled(loadingMore)
    }

    // MARK: - Actions

    private func runSearch() {
        searchTask?.cancel()
        let term = query
        searchTask = Task {
            // One completed search is 5–7 requests: USDA's stable datatypes, the
            // survey dataset with its retries, and three Open Food Facts country
            // tiers. At 400 ms an ordinary mid-word pause fired its own search, so
            // typing one word could cost three of those. 600 ms covers normal
            // typing gaps and still reads as instant.
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            searching = true
            loadedPage = 1

            // Results arrive per source rather than all at once, so the fast one
            // paints while the slow one is still in flight. The stream yields the
            // full ranked list each time, so this assigns rather than merges.
            for await page in FoodResolver(context: context)
                .stream(term, brand: store, region: region) {
                guard !Task.isCancelled else { return }
                results = page.foods
                hasMore = page.hasMore
                // Dropped on the first batch, not the last: leaving it up until
                // every source landed would keep a spinner over a list that is
                // already usable.
                searching = false
            }
            guard !Task.isCancelled else { return }
            searching = false
        }
    }

    /// Appends the next page. Deliberately a button rather than infinite scroll:
    /// each page is two network calls, and past the first 25 the results are
    /// rarely what was wanted — paging should be a decision, not a side effect
    /// of scrolling.
    private func loadMore() {
        guard !loadingMore, hasMore else { return }
        let term = query
        let next = loadedPage + 1
        loadingMore = true
        Task {
            let page = await FoodResolver(context: context).search(term, page: next,
                                                                   brand: store,
                                                                   region: region)
            guard !Task.isCancelled, term == query else {
                loadingMore = false
                return
            }
            let known = Set(results.map(\.id))
            results.append(contentsOf: page.foods.filter { !known.contains($0.id) })
            hasMore = page.hasMore
            loadedPage = next
            loadingMore = false
        }
    }

    private func delete(_ food: ResolvedFood) {
        FoodResolver(context: context).delete(food)
        results.removeAll { $0.id == food.id }
    }
}
