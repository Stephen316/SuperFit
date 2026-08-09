import SwiftUI
import SwiftData

struct CustomFoodView: View {
    let onCreated: (ResolvedFood) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// Which column of the label the numbers were copied from.
    ///
    /// UK and EU labels print per 100 g, US labels print per serving only, and
    /// entering one as the other is a silent 2-3x error on every macro. Asking
    /// costs one tap and removes the whole class of mistake.
    private enum Basis: String, CaseIterable, Identifiable {
        case per100g, perServing
        var id: String { rawValue }
        var label: String { self == .per100g ? "Per 100 g" : "Per serving" }
    }

    @State private var basis = Basis.per100g
    @State private var servingGrams: Double?
    @State private var name = ""
    @State private var brand = ""
    @State private var kcal: Double?
    @State private var protein: Double?
    @State private var carbs: Double?
    @State private var fat: Double?
    @State private var fibre: Double?

    var body: some View {
        NavigationStack {
            Form {
                Section("Food") {
                    TextField("Name", text: $name)
                    TextField("Brand (optional)", text: $brand)
                }
                Section {
                    FeatureTabControl(
                        options: Basis.allCases.map { ($0, $0.label) },
                        selection: $basis)
                        .accessibilityLabel("Nutrition label basis")
                    if basis == .perServing {
                        LabeledContent("Serving size") {
                            NumberField(title: "Serving size", unit: "g", value: $servingGrams)
                        }
                    }
                } header: {
                    Text("Label")
                } footer: {
                    Text(basis == .perServing
                         ? "Enter the serving weight and the numbers from the per-serving column."
                         : "Enter the numbers from the per-100 g column.")
                }

                Section(basis.label) {
                    field("Calories (kcal)", $kcal)
                    field("Protein (g)", $protein)
                    field("Carbs (g)", $carbs)
                    field("Fat (g)", $fat)
                    field("Fibre (g)", $fibre)
                }

                if basis == .perServing, let per100 = per100gPreview {
                    Section("Stored as per 100 g") {
                        LabeledContent("Calories", value: "\(Int(per100.kcal)) kcal")
                        LabeledContent("Protein", value: "\(Int(per100.proteinG)) g")
                        LabeledContent("Carbs", value: "\(Int(per100.carbsG)) g")
                        LabeledContent("Fat", value: "\(Int(per100.fatG)) g")
                    }
                }
            }
            .navigationTitle("Custom food")
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

    /// Everything is stored per 100 g, whichever column it was typed from.
    private var per100gPreview: NutrientProfile? {
        guard let kcal else { return nil }
        switch basis {
        case .per100g:
            return NutrientProfile(kcal: kcal, proteinG: protein ?? 0, carbsG: carbs ?? 0,
                                   fatG: fat ?? 0, fibreG: fibre ?? 0)
        case .perServing:
            guard let grams = servingGrams, grams > 0 else { return nil }
            let f = 100 / grams
            return NutrientProfile(kcal: kcal * f, proteinG: (protein ?? 0) * f,
                                   carbsG: (carbs ?? 0) * f, fatG: (fat ?? 0) * f,
                                   fibreG: (fibre ?? 0) * f)
        }
    }

    private var isValid: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.count <= 100 else { return false }
        if basis == .perServing, !(servingGrams ?? 0 > 0 && servingGrams! <= 2000) { return false }
        // Sanity-check the per-100 g figures, so a per-serving entry can't slip
        // an impossible density through by being small.
        guard let per100 = per100gPreview, per100.kcal >= 0, per100.kcal <= 900 else { return false }
        let macroKcal = 4 * per100.proteinG + 4 * per100.carbsG + 9 * per100.fatG
        return macroKcal <= per100.kcal * 1.3 + 20   // reject internally-inconsistent entries
    }

    private func field(_ label: String, _ value: Binding<Double?>) -> some View {
        LabeledContent(label) {
            NumberField(title: label, value: value)
        }
    }

    private func save() {
        guard let per100 = per100gPreview else { return }
        let food = Food(name: name.trimmingCharacters(in: .whitespaces), source: .custom)
        food.brand = brand.isEmpty ? nil : String(brand.prefix(100))
        food.kcalPer100g = per100.kcal
        food.proteinPer100g = per100.proteinG
        food.carbsPer100g = per100.carbsG
        food.fatPer100g = per100.fatG
        food.fibrePer100g = per100.fibreG
        // Keep the serving as a portion so "1 serving" is one tap when logging.
        if basis == .perServing, let grams = servingGrams, grams > 0 {
            food.portionsJSON = try? JSONEncoder().encode(
                [FoodPortion(label: "1 serving", gramWeight: grams)])
        }
        context.insert(food)
        try? context.save()
        dismiss()
        onCreated(food.resolved)
    }
}
