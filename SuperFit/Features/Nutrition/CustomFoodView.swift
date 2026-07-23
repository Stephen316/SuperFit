import SwiftUI
import SwiftData

struct CustomFoodView: View {
    let onCreated: (ResolvedFood) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

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
                Section("Per 100 g") {
                    field("Calories (kcal)", $kcal)
                    field("Protein (g)", $protein)
                    field("Carbs (g)", $carbs)
                    field("Fat (g)", $fat)
                    field("Fibre (g)", $fibre)
                }
            }
            .navigationTitle("Custom food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }.disabled(!isValid)
                }
            }
        }
    }

    private var isValid: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.count <= 100, let kcal, kcal >= 0, kcal <= 900 else { return false }
        let macroKcal = 4 * (protein ?? 0) + 4 * (carbs ?? 0) + 9 * (fat ?? 0)
        return macroKcal <= kcal * 1.3 + 20   // reject internally-inconsistent entries
    }

    private func field(_ label: String, _ value: Binding<Double?>) -> some View {
        LabeledContent(label) {
            TextField("0", value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
        }
    }

    private func save() {
        let food = Food(name: name.trimmingCharacters(in: .whitespaces), source: .custom)
        food.brand = brand.isEmpty ? nil : String(brand.prefix(100))
        food.kcalPer100g = kcal ?? 0
        food.proteinPer100g = protein ?? 0
        food.carbsPer100g = carbs ?? 0
        food.fatPer100g = fat ?? 0
        food.fibrePer100g = fibre ?? 0
        context.insert(food)
        try? context.save()
        dismiss()
        onCreated(food.resolved)
    }
}
