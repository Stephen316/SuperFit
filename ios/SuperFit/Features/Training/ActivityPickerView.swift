import SwiftUI
import SwiftData

/// The first screen behind "Start workout".
///
/// Strength keeps the existing flow — pick a template or an empty session, then
/// log sets. Everything else is a duration activity, and for those the useful
/// question isn't which exercise but *where the data comes from*: track it live
/// on the phone, or pull in what the watch already recorded.
struct ActivityPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \WorkoutTemplate.createdAt, order: .reverse)
    private var savedTemplates: [WorkoutTemplate]

    let recentWatchWorkouts: [WorkoutSample]
    /// Strength: nil template means an empty session.
    let onStartStrength: (WorkoutTemplate?) -> Void
    let onStartLive: (WorkoutActivity) -> Void
    let onImport: (WorkoutSample) -> Void

    @State private var search = ""
    @State private var editingTemplate: WorkoutTemplate?

    private var groups: [WorkoutActivity.Group] {
        WorkoutActivity.Group.allCases.filter { !activities(in: $0).isEmpty }
    }

    private func activities(in group: WorkoutActivity.Group) -> [WorkoutActivity] {
        let all = WorkoutActivity.inGroup(group)
        guard !search.isEmpty else { return all }
        return all.filter { $0.displayName.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            List {
                if search.isEmpty {
                    Group {
                        if !recentWatchWorkouts.isEmpty { recentSection }
                        strengthSection
                    }
                    .listRowBackground(Theme.surface)
                }

                ForEach(groups) { group in
                    if group != .strength || !search.isEmpty {
                        Section(group.rawValue) {
                            ForEach(activities(in: group)) { activity in
                                row(for: activity)
                            }
                        }
                        .listRowBackground(Theme.surface)
                    }
                }
            }
            .searchable(text: $search, prompt: "Find an activity")
            .navigationTitle("New workout")
            .themedChrome()
            .navigationBarTitleDisplayMode(.inline)
            .featureList()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                .withoutGlassBackground()
            }
        }
        .sheet(item: $editingTemplate) { template in
            WorkoutTemplateEditorView(template: template)
        }
    }

    /// Watch workouts not yet in the app, offered for one-tap import. This is the
    /// common case: the watch tracked it properly, the phone just needs to know.
    private var recentSection: some View {
        Section("From your watch") {
            ForEach(recentWatchWorkouts, id: \.externalID) { sample in
                Button {
                    onImport(sample)
                    dismiss()
                } label: {
                    HStack {
                        Image(systemName: sample.activity.symbolName)
                            .foregroundStyle(Theme.gold)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(sample.activity.displayName)
                            Text(sample.start, format: .dateTime.weekday().hour().minute())
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(Int(sample.durationSeconds / 60)) min")
                            .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                        Image(systemName: "square.and.arrow.down")
                            .font(.caption).foregroundStyle(Theme.gold)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var strengthSection: some View {
        Section {
            ForEach(savedTemplates) { template in
                Button {
                    onStartStrength(template)
                    dismiss()
                } label: {
                    Label(template.name, systemImage: "list.bullet.rectangle")
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        context.delete(template)
                        try? context.save()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    Button {
                        editingTemplate = template
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .tint(Theme.gold)
                }
            }
            Button {
                onStartStrength(nil)
                dismiss()
            } label: {
                Label("New gym workout", systemImage: "dumbbell.fill")
            }
            .buttonStyle(.plain)
        } header: {
            Text("Strength")
        } footer: {
            if savedTemplates.isEmpty {
                Text("Save a completed gym workout to reuse it here.")
            } else {
                Text("\(savedTemplates.count) of \(WorkoutTemplate.maximumSaved) saved. Swipe a saved workout left to edit or delete it.")
            }
        }
    }

    @ViewBuilder
    private func row(for activity: WorkoutActivity) -> some View {
        if activity.isStrength {
            Button {
                onStartStrength(nil)
                dismiss()
            } label: {
                activityLabel(activity)
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink {
                ActivityStartOptionsView(
                    activity: activity,
                    recent: recentWatchWorkouts.filter { $0.activity == activity },
                    onStartLive: { onStartLive(activity); dismiss() },
                    onImport: { onImport($0); dismiss() })
            } label: {
                activityLabel(activity)
            }
        }
    }

    private func activityLabel(_ activity: WorkoutActivity) -> some View {
        HStack {
            Image(systemName: activity.symbolName)
                .foregroundStyle(Theme.gold)
                .frame(width: 28)
            Text(activity.displayName)
        }
    }
}

private struct WorkoutTemplateEditorView: View {
    let template: WorkoutTemplate

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @Query private var templates: [WorkoutTemplate]

    @State private var name: String
    @State private var exerciseIDs: [UUID]
    @State private var pickingExercise = false
    @State private var errorMessage: String?

    init(template: WorkoutTemplate) {
        self.template = template
        _name = State(initialValue: template.name)
        _exerciseIDs = State(initialValue: template.orderedExerciseIDs)
    }

    private var trimmedName: String {
        String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(50))
    }

    private var canSave: Bool {
        !trimmedName.isEmpty && !exerciseIDs.isEmpty
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Saved workout") {
                    TextField("Workout name", text: $name)
                        .textInputAutocapitalization(.words)
                }
                .listRowBackground(Theme.surface)

                Section {
                    if exerciseIDs.isEmpty {
                        Text("Add at least one exercise.")
                            .foregroundStyle(Theme.textSecondary)
                    }
                    ForEach(exerciseIDs, id: \.self) { id in
                        Text(exercises.first { $0.id == id }?.name
                             ?? "Exercise no longer available")
                    }
                    .onDelete { exerciseIDs.remove(atOffsets: $0) }
                    .onMove { exerciseIDs.move(fromOffsets: $0, toOffset: $1) }

                    Button { pickingExercise = true } label: {
                        Label("Add exercise", systemImage: "plus")
                    }
                } header: {
                    Text("Exercises")
                } footer: {
                    Text("Starting this workout copies weights, reps, RIR and sets from its latest completed session. Every copied set starts unchecked.")
                }
                .listRowBackground(Theme.surface)
            }
            .navigationTitle("Edit saved workout")
            .navigationBarTitleDisplayMode(.inline)
            .themedChrome()
            .featureList(bottomPadding: 24)
            .keyboardDoneButton()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                .withoutGlassBackground()
                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                }
                .withoutGlassBackground()
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
                .withoutGlassBackground()
            }
            .sheet(isPresented: $pickingExercise) {
                ExercisePickerView { exercise in
                    if !exerciseIDs.contains(exercise.id) {
                        exerciseIDs.append(exercise.id)
                    }
                }
            }
            .alert("Couldn't save workout", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func save() {
        guard canSave else { return }
        if templates.contains(where: {
            $0.id != template.id
                && $0.name.caseInsensitiveCompare(trimmedName) == .orderedSame
        }) {
            errorMessage = "A saved workout named \"\(trimmedName)\" already exists. Choose another name."
            return
        }

        let oldName = template.name
        template.name = trimmedName
        for item in template.items ?? [] { context.delete(item) }
        for (order, exerciseID) in exerciseIDs.enumerated() {
            let item = WorkoutTemplateItem(order: order, exerciseID: exerciseID)
            item.template = template
            context.insert(item)
        }
        if oldName != trimmedName {
            // Only pay for historical session materialisation when the user
            // actually renames a template, not whenever the editor appears.
            let sessions = (try? context.fetch(FetchDescriptor<TrainingSession>())) ?? []
            for session in sessions where
                session.templateName?.caseInsensitiveCompare(oldName) == .orderedSame {
                session.templateName = trimmedName
            }
        }
        do {
            try context.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Live or from history, for one chosen activity.
struct ActivityStartOptionsView: View {
    let activity: WorkoutActivity
    let recent: [WorkoutSample]
    let onStartLive: () -> Void
    let onImport: (WorkoutSample) -> Void

    var body: some View {
        List {
            Section {
                Button(action: onStartLive) {
                    HStack {
                        Image(systemName: "record.circle")
                            .foregroundStyle(.red)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Start live").font(.headline)
                            Text(activity.usesLocation
                                 ? "Times the session and follows distance by GPS."
                                 : "Times the session on this phone.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
            } footer: {
                if activity.usesLocation {
                    Text("A watch records heart rate and route more accurately. "
                         + "Use this when the phone is all you have with you.")
                }
            }
            .listRowBackground(Theme.surface)

            Section("Recent \(activity.displayName.lowercased()) from your watch") {
                if recent.isEmpty {
                    Text("Nothing recorded yet.").foregroundStyle(.secondary)
                }
                ForEach(recent, id: \.externalID) { sample in
                    Button { onImport(sample) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(sample.start, format: .dateTime.weekday().day().month().hour().minute())
                                if let distance = sample.distanceMetres {
                                    Text(String(format: "%.2f km", distance / 1000))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text("\(Int(sample.durationSeconds / 60)) min")
                                .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .listRowBackground(Theme.surface)
        }
        .navigationTitle(activity.displayName)
        .themedChrome()
        .navigationBarTitleDisplayMode(.inline)
        .featureList()
    }
}
