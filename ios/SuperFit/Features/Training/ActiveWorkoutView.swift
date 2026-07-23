import SwiftUI
import SwiftData

struct ActiveWorkoutView: View {
    let session: TrainingSession

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var exercises: [Exercise]

    @State private var pickingExercise = false
    @State private var restEndsAt: Date?

    private var plannedExercises: [Exercise] {
        guard let name = session.templateName,
              let template = ExerciseLibrary.templates.first(where: { $0.name == name })
        else { return [] }
        return template.exercises.compactMap { n in exercises.first { $0.name == n } }
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(session.endedAt == nil ? "Finish" : "Done") { finish() }
                        .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $pickingExercise) {
                ExercisePickerView { exercise in
                    addSet(for: exercise)
                }
            }
        }
    }

    private func startRest(_ seconds: Int) {
        restEndsAt = Date().addingTimeInterval(TimeInterval(seconds))
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
        if session.endedAt == nil { session.endedAt = .now }
        try? context.save()
        dismiss()
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

    var body: some View {
        HStack(spacing: 10) {
            field("kg", value: Binding(get: { set.weightKg },
                                       set: { set.weightKg = $0.clamped(to: 0...500) }))
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

    /// Heavier, lower-RIR sets earn longer rest.
    private var defaultRest: Int {
        set.reps <= 6 ? 180 : 120
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
            .foregroundStyle(remaining > 0 ? .primary : .green)
        }
    }
}

struct ExercisePickerView: View {
    let onPick: (Exercise) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @State private var query = ""

    private var filtered: [Exercise] {
        query.isEmpty ? exercises
            : exercises.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { exercise in
                Button {
                    onPick(exercise)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(exercise.name).foregroundStyle(.primary)
                        Text(exercise.primaryMuscle.rawValue.capitalized)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .searchable(text: $query, prompt: "Search exercises")
            .navigationTitle("Add exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
            }
        }
    }
}
