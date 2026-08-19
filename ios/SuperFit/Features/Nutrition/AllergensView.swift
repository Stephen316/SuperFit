import SwiftUI

/// Picks the allergens to watch for, and is blunt about what the data can and
/// cannot tell you.
///
/// The caveat is not fine print here. Most of the food catalogue publishes no
/// allergen information at all, so the feature's honest output is "safe" or
/// "nothing published" — never "free from". The confirmation step exists so
/// that is read once, deliberately, rather than inferred from a missing tick.
struct AllergensView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AvoidedAllergens.storageKey) private var stored = ""

    @State private var selection: Set<Allergen> = []
    @State private var confirming = false

    var body: some View {
        NavigationStack {
            List {
                FeatureCategoryBar("What to watch for")
                    .listRowBackground(Theme.backgroundBase)
                    .listRowSeparator(.hidden)

                Section {
                    ForEach(Allergen.allCases) { allergen in
                        row(allergen)
                    }
                } footer: {
                    Text("The fourteen allergens Irish and UK labels must declare.")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                }
                .listRowBackground(Theme.surface)

                Section {
                    Label {
                        Text(Self.caveat)
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(Theme.gold)
                    }
                }
                .listRowBackground(Theme.surface)
            }
            .navigationTitle("Allergens")
            .themedChrome()
            .navigationBarTitleDisplayMode(.inline)
            .featureList()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { finish() }
                }
                .withoutGlassBackground()
            }
            .task { selection = AvoidedAllergens.decode(stored) }
            .alert("Not every food lists allergens", isPresented: $confirming) {
                Button("I understand") { save() }
                Button("Back", role: .cancel) {}
            } message: {
                Text(Self.caveat)
            }
        }
    }

    private static let caveat = """
        A blue tick appears only on foods whose label information we actually \
        hold, and that do not list what you avoid. Most foods publish nothing, \
        so no tick means "not stated" — never "safe". Always check the packet.
        """

    private func row(_ allergen: Allergen) -> some View {
        Button {
            if selection.contains(allergen) { selection.remove(allergen) }
            else { selection.insert(allergen) }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(allergen.label)
                        .foregroundStyle(Theme.textPrimary)
                    Text(allergen.examples)
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Image(systemName: selection.contains(allergen)
                      ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(selection.contains(allergen)
                                     ? Theme.gold : Theme.textSecondary.opacity(0.5))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selection.contains(allergen) ? .isSelected : [])
    }

    /// Clearing the list needs no warning — it turns the feature off. Only
    /// switching it on asks for the acknowledgement.
    private func finish() {
        if selection.isEmpty { save() } else { confirming = true }
    }

    private func save() {
        stored = AvoidedAllergens.encode(selection)
        dismiss()
    }
}
