import SwiftUI
import SwiftData

/// Pushed from Settings — no NavigationStack of its own.
struct ProfileView: View {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]
    @Query(sort: \BodyMetrics.date, order: .reverse) private var metrics: [BodyMetrics]
    @AppStorage(UnitSystem.storageKey) private var unitsRaw = UnitSystem.metric.rawValue

    @State private var bodyFatEntry = ""

    private var units: UnitSystem { UnitSystem(rawValue: unitsRaw) ?? .metric }
    private var profile: UserProfile? { profiles.first }
    private var latest: BodyMetrics? { metrics.first }

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

                bodyCompositionSection

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

    /// Body fat sharpens the basal estimate — but only a measured one.
    ///
    /// With lean mass known the engine switches to Katch-McArdle, which puts
    /// basal within ~27 kcal from a DEXA scan against Mifflin-St Jeor's typical
    /// ~180. That gain is entirely hostage to the input: 5 points of body-fat
    /// error moves basal by ~89 kcal, so a guessed figure buys nothing, and
    /// guesses skew low — which would inflate lean mass, inflate basal, and lift
    /// the calorie floor enough to block a legitimate deficit. Hence a single
    /// measured number and no estimate picker.
    @ViewBuilder
    private var bodyCompositionSection: some View {
        Section {
            if let latest {
                LabeledContent("Body fat") {
                    HStack(spacing: 4) {
                        TextField("—", text: $bodyFatEntry)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .onSubmit { saveBodyFat() }
                        Text("%").foregroundStyle(.secondary)
                        Button("Save", action: saveBodyFat)
                            .font(.caption)
                            .disabled(Double(bodyFatEntry).map { !(3...70).contains($0) } ?? true)
                    }
                }
                if let lean = latest.leanMassKg {
                    LabeledContent("Lean mass", value: units.weightString(lean))
                }
            } else {
                Text("Log your weight first — body fat attaches to a weigh-in.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        } header: {
            Text("Body composition")
        } footer: {
            Text(latest?.bodyFatPct == nil
                 ? "Optional. Enter it only if you've had it measured — DEXA, BodPod or hydrostatic. A measured figure improves your basal estimate; an eyeballed one doesn't, so leaving this blank is the better choice if you're unsure. Smart scales that write to Apple Health fill it in automatically."
                 : "Used for the Katch-McArdle basal estimate and to set protein from lean mass. Re-measure occasionally — it drifts as you gain or lose.")
        }
        .onAppear {
            if bodyFatEntry.isEmpty, let pct = latest?.bodyFatPct {
                bodyFatEntry = String(format: "%.1f", pct)
            }
        }
    }

    /// Attaches to the most recent weigh-in, since lean mass is only meaningful
    /// against the weight it was measured with.
    private func saveBodyFat() {
        guard let latest, let pct = Double(bodyFatEntry), (3...70).contains(pct) else { return }
        latest.bodyFatPct = pct
        latest.leanMassKg = latest.weightKg * (1 - pct / 100)
        try? context.save()
        AggregationService(context: context).runAll()
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
