import SwiftUI
import SwiftData

/// Pushed from Settings — no NavigationStack of its own.
struct ProfileView: View {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]
    @AppStorage(UnitSystem.storageKey) private var unitsRaw = UnitSystem.metric.rawValue

    private var units: UnitSystem { UnitSystem(rawValue: unitsRaw) ?? .metric }
    private var profile: UserProfile? { profiles.first }

    var body: some View {
        if let profile {
            Form {
                Section("Goal") {
                    Picker("Goal", selection: bind(profile, \.goal)) {
                        ForEach(FitnessGoal.allCases, id: \.self) { g in
                            Text(g.displayName).tag(g)
                        }
                    }
                }

                Section("About you") {
                    Picker("Sex", selection: bind(profile, \.sex)) {
                        Text("Male").tag(BiologicalSex.male)
                        Text("Female").tag(BiologicalSex.female)
                        Text("Other").tag(BiologicalSex.other)
                    }
                    DatePicker("Birth date",
                               selection: bind(profile, \.birthDate),
                               displayedComponents: .date)
                    LabeledContent("Height (\(units.heightUnit))") {
                        TextField(units.heightUnit,
                                  value: Binding(get: { units.displayHeight(profile.heightCm) },
                                                 set: { profile.heightCm = units.storeHeight($0)
                                                        try? context.save() }),
                                  format: .number.precision(.fractionLength(0...1)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                }

                Section("Activity baseline") {
                    Picker("Baseline", selection: bind(profile, \.activity)) {
                        ForEach(ActivityBaseline.allCases, id: \.self) { a in
                            Text(a.rawValue.capitalized).tag(a)
                        }
                    }
                    Text("Fallback only — replaced by measured Apple Health activity after ~a week of syncing, then by your logged trend data.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .themedList()
            .keyboardDoneButton()
        } else {
            ProgressView()
        }
    }

    private func bind<V>(_ profile: UserProfile, _ key: ReferenceWritableKeyPath<UserProfile, V>) -> Binding<V> {
        Binding(get: { profile[keyPath: key] },
                set: { profile[keyPath: key] = $0; try? context.save() })
    }
}

extension FitnessGoal {
    var displayName: String {
        switch self {
        case .fatLoss: return "Fat loss"
        case .maintenance: return "Maintenance"
        case .muscleGain: return "Muscle gain"
        case .recomposition: return "Recomposition"
        }
    }
}
