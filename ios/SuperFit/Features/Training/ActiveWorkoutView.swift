import SwiftUI
import SwiftData

struct ActiveWorkoutView: View {
    let session: TrainingSession

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var exercises: [Exercise]
    @Query private var savedTemplates: [WorkoutTemplate]

    @State private var pickingExercise = false
    @State private var didOfferFirstExercise = false
    @State private var restEndsAt: Date?
    @State private var savingTemplate = false
    @State private var templateName = ""
    @State private var confirmingOverwrite = false
    @State private var confirmingDiscard = false
    @State private var showingTemplateLimit = false
    @State private var showingRPE = false
    @State private var continueAfterRPE = false
    @State private var persistenceFailure: String?

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
                                    onSetCompleted: startRest,
                                    onSaveFailure: { persistenceFailure = $0 })
                }
                // Separated by weight rather than by a gap: "Add set" is a plain
                // row belonging to the exercise above it, while the one action
                // that operates on the whole workout is the only filled control
                // on the page. Styling sits inside the label so the whole
                // capsule is tappable, not just the text.
                Section {
                    Button {
                        pickingExercise = true
                    } label: {
                        Label("Add exercise", systemImage: "plus")
                            .font(Theme.text(16, .semibold))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(Capsule().fill(Theme.gold))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 14, leading: 16,
                                              bottom: 6, trailing: 16))
                }
                .listRowBackground(Theme.backgroundBase)
                .listRowSeparator(.hidden)

                // Carries the darker tone down past the last row. The list's own
                // empty area sits on the content surface, which otherwise leaves
                // a lighter slab under the add button.
                Color.clear
                    .frame(minHeight: 500)
                    .listRowBackground(Theme.backgroundBase)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets())
            }
            .navigationTitle(session.templateName ?? "Workout")
            .themedChrome()
            .navigationBarTitleDisplayMode(.inline)
            .featureList()
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
            // A new workout opens on an empty list, and the only useful first
            // action is adding an exercise. Once only: cancelling the picker is
            // a decision, and reopening it would trap the user in the sheet.
            .task {
                guard !didOfferFirstExercise, session.endedAt == nil,
                      exerciseSections.isEmpty else { return }
                didOfferFirstExercise = true
                pickingExercise = true
            }
            .sheet(isPresented: $showingRPE, onDismiss: {
                guard continueAfterRPE else { return }
                continueAfterRPE = false
                continueAfterEffortRating()
            }) {
                SessionRPEPrompt { rating in
                    session.sessionRPE = rating
                    guard saveChanges() else { return }
                    continueAfterRPE = true
                    showingRPE = false
                }
                .presentationDetents([.height(410)])
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
            .alert("Saved workout limit reached", isPresented: $showingTemplateLimit) {
                Button("Manage saved workouts") {
                    discardIfEmpty()
                    if saveChanges() { dismiss() }
                }
                Button("Keep editing", role: .cancel) {}
            } message: {
                Text("You can save up to 8 workouts. Delete a previous saved workout from New workout before saving another.")
            }
            .alert("No sets completed", isPresented: $confirmingDiscard) {
                // A fresh session with exercises is worth keeping as a plan even
                // when nothing was done — that is what "saved workouts" are for.
                if session.templateName == nil, !performedExerciseIDs.isEmpty {
                    Button("Save as workout") { templateName = ""; savingTemplate = true }
                }
                Button("Discard workout", role: .destructive) { discard() }
                Button("Keep going", role: .cancel) {}
            } message: {
                Text("Tick a set as you finish it to log it. Nothing here counts as "
                     + "trained yet, so this workout won't be saved.")
            }
            .alert("Couldn't save workout", isPresented: Binding(
                get: { persistenceFailure != nil },
                set: { if !$0 { persistenceFailure = nil } })) {
                Button("OK", role: .cancel) { persistenceFailure = nil }
            } message: {
                Text(persistenceFailure ?? "")
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

    /// Completed, non-warmup sets. Nothing here means nothing was trained.
    private var completedSetCount: Int {
        (session.sets ?? []).filter { $0.completedAt != nil && !$0.isWarmup }.count
    }

    private func saveTemplate() {
        guard !trimmedTemplateName.isEmpty else { dismiss(); return }
        if existingTemplate != nil {
            confirmingOverwrite = true
            return
        }
        guard WorkoutTemplate.canCreate(savedCount: savedTemplates.count) else {
            Task { @MainActor in showingTemplateLimit = true }
            return
        }
        session.templateName = trimmedTemplateName
        let template = WorkoutTemplate(name: trimmedTemplateName)
        context.insert(template)
        setItems(on: template)
        discardIfEmpty()
        if saveChanges() { dismiss() }
    }

    private func overwriteTemplate() {
        guard let existing = existingTemplate else { dismiss(); return }
        session.templateName = existing.name
        for item in existing.items ?? [] { context.delete(item) }
        setItems(on: existing)
        discardIfEmpty()
        if saveChanges() { dismiss() }
    }

    /// After saving the plan, bin the session itself if nothing was completed —
    /// the exercise list lives on as the template, but an empty session must not
    /// linger in the store.
    private func discardIfEmpty() {
        if completedSetCount == 0 { context.delete(session) }
    }

    private func discard() {
        context.delete(session)
        if saveChanges() { dismiss() }
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
                             weightKg: previous?.weightKg,
                             reps: previous?.reps ?? SetRow.defaultReps)
        entry.session = session
        context.insert(entry)
        saveChanges()
    }

    private func finish() {
        // Nothing ticked means nothing was done. Confirm before it's binned
        // rather than leave an empty session in history.
        guard completedSetCount > 0 else {
            confirmingDiscard = true
            return
        }
        guard session.endedAt == nil else { dismiss(); return }
        session.endedAt = .now
        if saveChanges() { showingRPE = true }
    }

    private func continueAfterEffortRating() {
        // Offer template save only when finishing a non-template session with sets.
        if session.templateName == nil, !performedExerciseIDs.isEmpty {
            templateName = ""
            savingTemplate = true
        } else {
            dismiss()
        }
    }

    @discardableResult
    private func saveChanges() -> Bool {
        do {
            try context.save()
            return true
        } catch {
            persistenceFailure = error.localizedDescription
            return false
        }
    }
}

private struct ExerciseSection: View {
    let session: TrainingSession
    let exercise: Exercise
    let onSetCompleted: (Int) -> Void
    let onSaveFailure: (String) -> Void

    @Environment(\.modelContext) private var context

    private var sets: [SetEntry] {
        (session.sets ?? []).filter { $0.exerciseID == exercise.id }.sorted { $0.order < $1.order }
    }

    var body: some View {
        // The name gets the darker bar and the sets the lighter surface, so the
        // two alternate. A plain `Section(header:)` picked up neither and the
        // whole block read as one flat colour.
        FeatureCategoryBar(exercise.name)
            .listRowBackground(Theme.backgroundBase)
            .listRowSeparator(.hidden)
        Section {
            ForEach(sets) { set in
                SetRow(set: set, onCompleted: onSetCompleted,
                       onSaveFailure: onSaveFailure)
            }
            .onDelete { offsets in
                for i in offsets { context.delete(sets[i]) }
                saveChanges()
            }
            Button {
                let entry = SetEntry(order: ((session.sets ?? []).map(\.order).max() ?? 0) + 1,
                                     exerciseID: exercise.id,
                                     weightKg: sets.last?.weightKg,
                                     reps: sets.last?.reps ?? SetRow.defaultReps)
                entry.session = session
                context.insert(entry)
                saveChanges()
            } label: {
                Label("Add set", systemImage: "plus").font(.subheadline)
            }
        }
        // The sets and their Add row take the content surface; the exercise
        // name keeps the darker header behind it, so the two alternate the way
        // a category bar and its rows do everywhere else.
        .listRowBackground(Theme.surface)
    }

    private func saveChanges() {
        do { try context.save() }
        catch { onSaveFailure(error.localizedDescription) }
    }
}

private struct SetRow: View {
    @Bindable var set: SetEntry
    let onCompleted: (Int) -> Void
    let onSaveFailure: (String) -> Void

    @Environment(\.modelContext) private var context
    @AppStorage(UnitSystem.storageKey) private var unitsRaw = UnitSystem.metric.rawValue

    @State private var editing: Field?

    private var units: UnitSystem { UnitSystem(rawValue: unitsRaw) ?? .metric }

    /// Which cell the entry sheet is editing. `Identifiable` so it drives a
    /// `.sheet(item:)` — one sheet, whichever cell was tapped.
    private enum Field: Identifiable {
        case weight, reps
        var id: Int { self == .weight ? 0 : 1 }
    }

    var body: some View {
        HStack(spacing: 10) {
            // Tap targets, not inline text fields. The old fields dropped the
            // caret at the *left* of the digits, so correcting one meant tapping
            // precisely to the right before backspacing. These open a sheet with
            // an empty box instead, so a value is always typed fresh.
            cell(weightText, unit: units.weightUnit) { editing = .weight }
            cell("\(set.reps)", unit: "reps") { editing = .reps }

            Picker("RIR", selection: Binding(get: { set.rir ?? -1 },
                                             set: {
                                                 set.rir = $0 < 0 ? nil : $0
                                                 saveChanges()
                                             })) {
                Text("RIR").tag(-1)
                ForEach(0...5, id: \.self) { Text("\($0)").tag($0) }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            Spacer()
            Button {
                let done = set.completedAt != nil
                set.completedAt = done ? nil : .now
                if saveChanges(), !done { onCompleted(defaultRest) }
            } label: {
                Image(systemName: set.completedAt != nil ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(set.completedAt != nil ? .green : .secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)
        }
        .fullScreenCover(item: $editing) { field in
            switch field {
            case .weight:
                NumberEntrySheet(title: "Weight", unit: units.weightUnit, allowsDecimal: true) { value in
                    // Blank sets it back to "—"; a typed 0 is kept. Both are the
                    // user's choice, which is the whole point of the "—" default.
                    set.weightKg = value.map { units.storeWeight($0).clamped(to: 0...500) }
                    saveChanges()
                }
            case .reps:
                NumberEntrySheet(title: "Reps", unit: "reps", allowsDecimal: false) { value in
                    // Blank restores the default rather than leaving reps empty.
                    set.reps = value.map { Int($0.clamped(to: 0...100)) } ?? Self.defaultReps
                    saveChanges()
                }
            }
        }
    }

    /// Reps a fresh set starts at, and what a blank entry restores.
    static let defaultReps = 8

    /// Placeholder shown until a weight is entered.
    static let unset = "--"

    /// The weight cell's text: the number, or "--" until one is entered.
    private var weightText: String {
        guard let kg = set.weightKg else { return Self.unset }
        let shown = units.displayWeight(kg)
        return shown == shown.rounded()
            ? String(Int(shown))
            : String(format: "%.1f", shown)
    }

    /// Heavier, lower-rep sets earn longer rest. (`return` is required: the
    /// property is named `set`, so a body starting with `set.` parses as a
    /// setter declaration.)
    private var defaultRest: Int {
        return set.reps <= 6 ? 180 : 120
    }

    /// A tappable value cell that reads like an editable field.
    private func cell(_ text: String, unit: String, tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            HStack(spacing: 2) {
                Text(text)
                    .monospacedDigit()
                    .foregroundStyle(text == Self.unset ? .secondary : .primary)
                    .frame(minWidth: 34, alignment: .trailing)
                Text(unit).font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Theme.wash))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    @discardableResult
    private func saveChanges() -> Bool {
        do {
            try context.save()
            return true
        } catch {
            onSaveFailure(error.localizedDescription)
            return false
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
    /// The lift whose how-to and history are being shown.
    @State private var info: Exercise?

    private var filtered: [Exercise] {
        exercises.filter { e in
            // `matches` also checks the alias list, so "OHP" or "RDL" finds the
            // lift while the row still shows its catalogue name.
            // Direct work only, matching the muscles the row lists. At >= 3 the
            // filter returned lifts that merely assist the chosen muscle and
            // never name it, so filtering by triceps surfaced bench presses.
            e.matches(query)
            && (muscleFilter == nil
                || (e.tension[muscleFilter!] ?? 0) >= TensionRow.directThreshold)
        }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { exercise in
              HStack(spacing: 0) {
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
                                    .background(Theme.track)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                        }
                        TensionRow(tension: exercise.tension)
                    }
                    // Reserves the trailing gutter the info button sits in, so the
                    // tension list wraps before it reaches the icon rather than
                    // running underneath it.
                    .padding(.trailing, 34)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)

                // A sibling of the picking button, not an overlay on it: tapping
                // "i" must open the detail rather than silently add the lift.
                Button { info = exercise } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 17))
                        .foregroundStyle(Theme.gold)
                        .frame(width: 34, height: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("How to do \(exercise.name)")
              }
              .listRowBackground(Theme.surface)
            }
            .sheet(item: $info) { ExerciseInfoView(exercise: $0) }
            .searchable(text: $query, prompt: "Search exercises")
            .navigationTitle("Add exercise")
            .themedChrome()
            .navigationBarTitleDisplayMode(.inline)
            .featureList()
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
            }
        }
    }
}

/// "Chest 5 · Triceps 3 · Shoulders 2" — the per-muscle tension breakdown.
/// The muscles an exercise trains directly.
///
/// Only tension ≥ 4, the threshold at which a set counts as a whole direct set
/// rather than assistance, and the score itself is never shown. The number is a
/// model input; picking an exercise only needs the answer to "what does this
/// train", and 4 versus 5 is not a distinction to act on at the rack.
struct TensionRow: View {
    /// Where a set stops being assistance and counts as direct work. Shared
    /// with the picker's muscle filter so the list it returns and the muscles
    /// each row names can never disagree.
    static let directThreshold = 4

    let tension: [MuscleGroup: Int]

    private var directMuscles: String {
        tension.filter { $0.value >= Self.directThreshold }
            .sorted {
                $0.value != $1.value ? $0.value > $1.value
                                     : $0.key.displayName < $1.key.displayName
            }
            .map(\.key.displayName)
            .joined(separator: " · ")
    }

    var body: some View {
        // Nothing rather than an empty line: a few catalogue entries are all
        // assistance, and a blank caption would leave a gap under the name.
        if !directMuscles.isEmpty {
            Text(directMuscles)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
