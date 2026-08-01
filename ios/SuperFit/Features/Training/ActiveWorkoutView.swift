import SwiftUI
import SwiftData

struct ActiveWorkoutView: View {
    let session: TrainingSession

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var exercises: [Exercise]
    @Query private var savedTemplates: [WorkoutTemplate]

    @State private var pickingExercise = false
    @State private var restEndsAt: Date?
    @State private var savingTemplate = false
    @State private var templateName = ""
    @State private var confirmingOverwrite = false

    private var plannedExercises: [Exercise] {
        guard let name = session.templateName,
              let saved = savedTemplates.first(where: { $0.name == name })
        else { return [] }
        return saved.orderedExerciseIDs.compactMap { id in exercises.first { $0.id == id } }
    }

    /// Exercises with logged sets, in first-set order; planned-but-unstarted after.
    private var exerciseSections: [Exercise] {
        let sets = (session.sets ?? []).sorted { $0.order < $1.order }
        var seen: [UUID] = []
        for s in sets {
            if let id = s.exerciseID, !seen.contains(id) { seen.append(id) }
        }
        let started = seen.compactMap { id in exercises.first { $0.id == id } }
        let pending = plannedExercises.filter { p in !seen.contains(p.id) }
        return started + pending
    }

    var body: some View {
        NavigationStack {
            List {
                if let restEndsAt {
                    RestTimerRow(endsAt: restEndsAt) { self.restEndsAt = nil }
                }
                ForEach(exerciseSections) { exercise in
                    ExerciseSection(session: session, exercise: exercise,
                                    onSetCompleted: startRest)
                }
                Section {
                    Button {
                        pickingExercise = true
                    } label: {
                        Label("Add exercise", systemImage: "plus")
                    }
                }
            }
            .navigationTitle(session.templateName ?? "Workout")
            .themedChrome()
            .navigationBarTitleDisplayMode(.inline)
            .themedList()
            .keyboardDoneButton()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                .withoutGlassBackground()
                ToolbarItem(placement: .topBarTrailing) {
                    Button(session.endedAt == nil ? "Finish" : "Done") { finish() }
                        .fontWeight(.semibold)
                }
                .withoutGlassBackground()
            }
            .sheet(isPresented: $pickingExercise) {
                ExercisePickerView { exercise in
                    addSet(for: exercise)
                }
            }
            .alert("Save as workout", isPresented: $savingTemplate) {
                TextField("Name", text: $templateName)
                Button("Save") { saveTemplate() }
                Button("Not now", role: .cancel) { dismiss() }
            } message: {
                Text("Reuse this exercise list from the start menu anytime.")
            }
            .alert("\"\(trimmedTemplateName)\" already exists", isPresented: $confirmingOverwrite) {
                Button("Overwrite", role: .destructive) { overwriteTemplate() }
                Button("Cancel", role: .cancel) {
                    Task { @MainActor in savingTemplate = true }   // back to naming
                }
            } message: {
                Text("Replace the existing workout with this one, or cancel to pick a different name.")
            }
        }
    }

    private func startRest(_ seconds: Int) {
        restEndsAt = Date().addingTimeInterval(TimeInterval(seconds))
    }

    /// Distinct exercises in first-set order — what a saved template captures.
    private var performedExerciseIDs: [UUID] {
        var seen: [UUID] = []
        for s in (session.sets ?? []).sorted(by: { $0.order < $1.order }) {
            if let id = s.exerciseID, !seen.contains(id) { seen.append(id) }
        }
        return seen
    }

    private var trimmedTemplateName: String {
        String(templateName.trimmingCharacters(in: .whitespaces).prefix(50))
    }

    private var existingTemplate: WorkoutTemplate? {
        savedTemplates.first { $0.name.caseInsensitiveCompare(trimmedTemplateName) == .orderedSame }
    }

    private func saveTemplate() {
        guard !trimmedTemplateName.isEmpty else { dismiss(); return }
        if existingTemplate != nil {
            confirmingOverwrite = true
            return
        }
        let template = WorkoutTemplate(name: trimmedTemplateName)
        context.insert(template)
        setItems(on: template)
        try? context.save()
        dismiss()
    }

    private func overwriteTemplate() {
        guard let existing = existingTemplate else { dismiss(); return }
        for item in existing.items ?? [] { context.delete(item) }
        setItems(on: existing)
        try? context.save()
        dismiss()
    }

    private func setItems(on template: WorkoutTemplate) {
        for (i, id) in performedExerciseIDs.enumerated() {
            let item = WorkoutTemplateItem(order: i, exerciseID: id)
            item.template = template
            context.insert(item)
        }
    }

    private func addSet(for exercise: Exercise) {
        let sets = session.sets ?? []
        let previous = sets.filter { $0.exerciseID == exercise.id }.max { $0.order < $1.order }
        let entry = SetEntry(order: (sets.map(\.order).max() ?? 0) + 1,
                             exerciseID: exercise.id,
                             weightKg: previous?.weightKg ?? 0,
                             reps: previous?.reps ?? 8)
        entry.session = session
        context.insert(entry)
        try? context.save()
    }

    private func finish() {
        let firstFinish = session.endedAt == nil
        if firstFinish { session.endedAt = .now }
        try? context.save()
        // Offer template save only when finishing a non-template session with sets.
        if firstFinish, session.templateName == nil, !performedExerciseIDs.isEmpty {
            templateName = ""
            savingTemplate = true
        } else {
            dismiss()
        }
    }
}

private struct ExerciseSection: View {
    let session: TrainingSession
    let exercise: Exercise
    let onSetCompleted: (Int) -> Void

    @Environment(\.modelContext) private var context

    private var sets: [SetEntry] {
        (session.sets ?? []).filter { $0.exerciseID == exercise.id }.sorted { $0.order < $1.order }
    }

    var body: some View {
        Section(exercise.name) {
            ForEach(sets) { set in
                SetRow(set: set, onCompleted: onSetCompleted)
            }
            .onDelete { offsets in
                for i in offsets { context.delete(sets[i]) }
                try? context.save()
            }
            Button {
                let entry = SetEntry(order: ((session.sets ?? []).map(\.order).max() ?? 0) + 1,
                                     exerciseID: exercise.id,
                                     weightKg: sets.last?.weightKg ?? 0,
                                     reps: sets.last?.reps ?? 8)
                entry.session = session
                context.insert(entry)
                try? context.save()
            } label: {
                Label("Add set", systemImage: "plus").font(.subheadline)
            }
        }
    }
}

private struct SetRow: View {
    @Bindable var set: SetEntry
    let onCompleted: (Int) -> Void

    @Environment(\.modelContext) private var context
    @AppStorage(UnitSystem.storageKey) private var unitsRaw = UnitSystem.metric.rawValue

    private var units: UnitSystem { UnitSystem(rawValue: unitsRaw) ?? .metric }

    var body: some View {
        HStack(spacing: 10) {
            field(units.weightUnit,
                  value: Binding(get: { units.displayWeight(set.weightKg) },
                                 set: { set.weightKg = units.storeWeight($0).clamped(to: 0...500) }))
            field("reps", value: Binding(get: { Double(set.reps) },
                                         set: { set.reps = Int($0.clamped(to: 0...100)) }))
            Picker("RIR", selection: Binding(get: { set.rir ?? -1 },
                                             set: { set.rir = $0 < 0 ? nil : $0 })) {
                Text("RIR").tag(-1)
                ForEach(0...5, id: \.self) { Text("\($0)").tag($0) }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            Spacer()
            Button {
                let done = set.completedAt != nil
                set.completedAt = done ? nil : .now
                try? context.save()
                if !done { onCompleted(defaultRest) }
            } label: {
                Image(systemName: set.completedAt != nil ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(set.completedAt != nil ? .green : .secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)
        }
    }

    /// Heavier, lower-rep sets earn longer rest. (`return` is required: the
    /// property is named `set`, so a body starting with `set.` parses as a
    /// setter declaration.)
    private var defaultRest: Int {
        return set.reps <= 6 ? 180 : 120
    }

    private func field(_ unit: String, value: Binding<Double>) -> some View {
        HStack(spacing: 2) {
            TextField("0", value: value, format: .number.precision(.fractionLength(0...1)))
                .keyboardType(.decimalPad)
                .frame(width: 48)
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.roundedBorder)
            Text(unit).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

private struct RestTimerRow: View {
    let endsAt: Date
    let onDismiss: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let remaining = max(0, endsAt.timeIntervalSince(timeline.date))
            HStack {
                Image(systemName: "timer")
                Text(remaining > 0
                     ? "Rest \(Int(remaining) / 60):\(String(format: "%02d", Int(remaining) % 60))"
                     : "Rest done — go")
                    .monospacedDigit()
                Spacer()
                Button("Skip", action: onDismiss).font(.subheadline)
            }
            .foregroundStyle(remaining > 0 ? Color.primary : Color.green)
        }
    }
}

struct ExercisePickerView: View {
    let onPick: (Exercise) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @State private var query = ""
    @State private var muscleFilter: MuscleGroup?
    @State private var creatingCustom = false

    private var filtered: [Exercise] {
        exercises.filter { e in
            // `matches` also checks the alias list, so "OHP" or "RDL" finds the
            // lift while the row still shows its catalogue name.
            e.matches(query)
            && (muscleFilter == nil || (e.tension[muscleFilter!] ?? 0) >= 3)
        }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { exercise in
                Button {
                    onPick(exercise)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(exercise.name).foregroundStyle(.primary)
                            if exercise.isCustom {
                                Text("Custom").font(.caption2)
                                    .padding(.horizontal, 5).padding(.vertical, 1)
                                    .background(Color.white.opacity(0.12))
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                        }
                        TensionRow(tension: exercise.tension)
                    }
                }
            }
            .searchable(text: $query, prompt: "Search exercises")
            .navigationTitle("Add exercise")
            .themedChrome()
            .navigationBarTitleDisplayMode(.inline)
            .themedList()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                .withoutGlassBackground()
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("All muscles") { muscleFilter = nil }
                        ForEach(MuscleGroup.allCases, id: \.self) { m in
                            Button(m.displayName) { muscleFilter = m }
                        }
                    } label: {
                        Image(systemName: muscleFilter == nil
                              ? "line.3.horizontal.decrease.circle"
                              : "line.3.horizontal.decrease.circle.fill")
                    }
                }
                .withoutGlassBackground()
                ToolbarItem(placement: .topBarTrailing) {
                    Button { creatingCustom = true } label: { Image(systemName: "plus") }
                }
                .withoutGlassBackground()
            }
            .sheet(isPresented: $creatingCustom) {
                CustomExerciseView { exercise in
                    onPick(exercise)
                    dismiss()
                }
            }
        }
    }
}

/// "Chest 5 · Triceps 3 · Shoulders 2" — the per-muscle tension breakdown.
struct TensionRow: View {
    let tension: [MuscleGroup: Int]

    var body: some View {
        Text(tension.sorted { $0.value > $1.value }
            .map { "\($0.key.displayName) \($0.value)" }
            .joined(separator: " · "))
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

struct CustomExerciseView: View {
    let onCreated: (Exercise) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var category = ExerciseCategory.barbell
    @State private var scores: [MuscleGroup: Int] = [:]

    private var isValid: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty && trimmed.count <= 60 && scores.values.contains { $0 > 0 }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Exercise name", text: $name)
                    Picker("Equipment", selection: $category) {
                        Text("Barbell").tag(ExerciseCategory.barbell)
                        Text("Dumbbell").tag(ExerciseCategory.dumbbell)
                        Text("Machine").tag(ExerciseCategory.machine)
                        Text("Cable").tag(ExerciseCategory.cable)
                        Text("Bodyweight").tag(ExerciseCategory.bodyweight)
                    }
                }
                Section {
                    ForEach(MuscleGroup.allCases, id: \.self) { muscle in
                        Stepper(value: Binding(get: { scores[muscle] ?? 0 },
                                               set: { scores[muscle] = $0 }),
                                in: 0...5) {
                            HStack {
                                Text(muscle.displayName)
                                Spacer()
                                Text("\(scores[muscle] ?? 0)")
                                    .monospacedDigit()
                                    .foregroundStyle((scores[muscle] ?? 0) > 0 ? .primary : .secondary)
                            }
                        }
                    }
                } header: {
                    Text("Muscle tension (0–5)")
                } footer: {
                    Text("5 = prime mover under maximal tension, 1 = lightly involved, 0 = not trained. Drives weekly volume tracking.")
                }
            }
            .navigationTitle("New exercise")
            .themedChrome()
            .navigationBarTitleDisplayMode(.inline)
            .themedList()
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

    private func save() {
        let tension = scores.filter { $0.value > 0 }
        let exercise = Exercise(name: name.trimmingCharacters(in: .whitespaces),
                                category: category, tension: tension, isCustom: true)
        context.insert(exercise)
        try? context.save()
        dismiss()
        onCreated(exercise)
    }
}
