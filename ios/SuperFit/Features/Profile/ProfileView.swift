import SwiftUI
import SwiftData

struct ProfileView: View {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]

    private var profile: UserProfile? { profiles.first }

    var body: some View {
        NavigationStack {
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
                        LabeledContent("Height") {
                            TextField("cm", value: bind(profile, \.heightCm), format: .number)
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
                        Text("Used only until your logged data measures your real expenditure.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .navigationTitle("Profile")
            } else {
                ProgressView().navigationTitle("Profile")
            }
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
