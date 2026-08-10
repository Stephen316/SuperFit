import SwiftUI
import SwiftData

struct TrainingView: View {
    @Environment(\.modelContext) private var context
    @Query private var sessions: [TrainingSession]
    @Query private var exercises: [Exercise]
    @Query(sort: \WorkoutTemplate.createdAt, order: .reverse) private var savedTemplates: [WorkoutTemplate]

    @Query private var workouts: [WorkoutRecord]
    @Query private var loadWorkouts: [WorkoutRecord]
    @Query private var profiles: [UserProfile]
    @Query private var vitals: [DailyVitals]

    @State private var activeSession: TrainingSession?
    @State private var watch = WatchWorkoutMonitor()
    @State private var showingPicker = false
    @State private var showingMuscleBreakdown = false
    @State private var muscleQuery = ""
    @State private var leastTrainedFirst = false
    @State private var liveActivity: WorkoutActivity?
    @State private var detailWorkout: WorkoutRecord?
    @State private var persistenceFailure: String?
    @AppStorage(UnitSystem.storageKey) private var unitsRaw = UnitSystem.metric.rawValue

    init() {
        let sessionCutoff = Date.now.addingTimeInterval(-60 * 86_400)
        _sessions = Query(filter: #Predicate { $0.startedAt >= sessionCutoff },
                          sort: \TrainingSession.startedAt, order: .reverse)

        var recentWorkouts = FetchDescriptor<WorkoutRecord>(
            sortBy: [SortDescriptor(\WorkoutRecord.startedAt, order: .reverse)])
        recentWorkouts.fetchLimit = 30
        _workouts = Query(recentWorkouts)

        let loadCutoff = Date.now.addingTimeInterval(-28 * 86_400)
        _loadWorkouts = Query(filter: #Predicate { $0.startedAt > loadCutoff })

        var latestRestingHR = FetchDescriptor<DailyVitals>(
            predicate: #Predicate { $0.restingHR != nil },
            sortBy: [SortDescriptor(\DailyVitals.date, order: .reverse)])
        latestRestingHR.fetchLimit = 1
        _vitals = Query(latestRestingHR)
    }

    private var units: UnitSystem { UnitSystem(rawValue: unitsRaw) ?? .metric }

    private var allRecords: [LiftRecord] {
        let fractions = Dictionary(exercises.map { ($0.id, $0.bodyweightFraction) },
                                   uniquingKeysWith: { a, _ in a })
        return TrainingRecords.completed(sessions, fractions: fractions)
    }

    /// One row of the weekly table.
    ///
    /// Carries the whole `EffectiveVolume` rather than a flattened number,
    /// because the row shows the direct count, sorts on the effective total, and
    /// colours on both — and those are three different questions.
    private struct MuscleRow: Identifiable {
        let muscle: MuscleGroup
        let volume: VolumeAggregator.EffectiveVolume?

        var id: MuscleGroup { muscle }

        var sets: Int { volume?.direct ?? 0 }
        var secondary: Int { volume?.secondary ?? 0 }
        /// Sorts. Direct sets plus the capped assisting credit.
        var effective: Double { volume?.effective ?? 0 }

        /// Worked, but never as the target — the biceps after a pull day.
        var isSecondaryOnly: Bool { volume?.isSecondaryOnly ?? false }

        /// The number the row prints, whichever kind of set it is.
        var displayedSets: Int { sets > 0 ? sets : secondary }
    }

    /// Rows for the weekly table: every group, whether trained or not.
    ///
    /// Including the untrained ones is the point — "least trained first" is
    /// meaningless if a muscle you never touched simply isn't in the list, and
    /// the gap is what the table exists to show.
    private func weeklyRows(_ volume: [MuscleGroup: VolumeAggregator.EffectiveVolume])
        -> [MuscleRow] {
        let term = muscleQuery.trimmingCharacters(in: .whitespaces)
        return MuscleGroup.allCases
            .map { MuscleRow(muscle: $0, volume: volume[$0]) }
            .filter { term.isEmpty || $0.muscle.displayName.localizedCaseInsensitiveContains(term) }
            .sorted { a, b in
                // Alphabetical tiebreak so the many zero rows keep a stable,
                // findable order instead of shuffling on every redraw.
                if a.effective != b.effective {
                    return leastTrainedFirst ? a.effective < b.effective : a.effective > b.effective
                }
                return a.muscle.displayName < b.muscle.displayName
            }
    }

    /// Tension map per exercise.
    ///
    /// `uniquingKeysWith`, not `uniqueKeysWithValues`, for the same reason
    /// `allRecords` above uses it: nothing in the schema stops two rows sharing
    /// an id after a CloudKit merge or an archive restore, and the trapping
    /// initialiser would take the app down rather than draw a table.
    private var muscleTension: [UUID: [MuscleGroup: Int]] {
        Dictionary(exercises.map { ($0.id, $0.tension) }, uniquingKeysWith: { a, _ in a })
    }

    /// The ISO week containing today. `Calendar(identifier: .iso8601)` already
    /// carries Monday as its first weekday and a 4-day minimum first week, so
    /// nothing needs setting.
    private var currentWeek: DateInterval? {
        Calendar(identifier: .iso8601).dateInterval(of: .weekOfYear, for: .now)
    }

    /// One pass over the week, since the table, the ordering and the diagram all
    /// read the same figures.
    ///
    /// Expensive — it walks every set of every session — so `body` computes it
    /// **once** and hands the result down. It used to be read straight from the
    /// diagram's `rank` and `colour` closures, which `Canvas` calls per region
    /// while drawing: one tap on this tab recomputed the whole training history
    /// 339 times, 380 ms of it on a store holding a single session, and growing
    /// with every workout logged.
    private var thisWeekVolume: [MuscleGroup: VolumeAggregator.EffectiveVolume] {
        guard let week = currentWeek else { return [:] }
        return VolumeAggregator().weeklyVolume(records: allRecords,
                                               muscles: muscleTension, week: week)
    }

    /// Whether a session logged real work — at least one completed, non-warmup
    /// set. A session that was started and abandoned without ticking anything is
    /// a plan, not a workout, so it stays out of the history lists.
    static func hasCompletedWork(_ session: TrainingSession) -> Bool {
        (session.sets ?? []).contains { $0.completedAt != nil && !$0.isWarmup }
    }

    /// Gym sessions started today that actually logged a set.
    private var todaySessions: [TrainingSession] {
        sessions.filter {
            Calendar.current.isDateInToday($0.startedAt) && Self.hasCompletedWork($0)
        }
    }

    /// Watch strength records are retained for heart rate, but their overlapping
    /// phone session is the single row the user sees.
    private var displayedWorkouts: [WorkoutRecord] {
        let completed = sessions.compactMap { session -> DateInterval? in
            guard Self.hasCompletedWork(session), let end = session.endedAt,
                  end > session.startedAt else { return nil }
            return DateInterval(start: session.startedAt, end: end)
        }
        let strengthIndices = workouts.indices.filter {
            workouts[$0].activity.isStrength && workouts[$0].durationSeconds > 0
        }
        let matched = Set(WorkoutTimeMatcher.matches(
            workouts: strengthIndices.map {
                DateInterval(start: workouts[$0].startedAt, end: workouts[$0].endedAt)
            }, sessions: completed).keys.map { strengthIndices[$0] })
        return workouts.enumerated().compactMap { matched.contains($0.offset) ? nil : $0.element }
    }

    /// The seven days before today, newest first, grouped by day.
    ///
    /// Today is excluded because it has its own section — carrying it in both
    /// would make one workout look like two, and the point of splitting them is
    /// to answer "have I trained today" without reading a list.
    ///
    /// Only days that actually hold a session appear. An empty day would be a
    /// row saying nothing, and seven of them would bury the days that matter.
    private var recentSessionDays: [(day: Date, sessions: [TrainingSession])] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        guard let from = cal.date(byAdding: .day, value: -7, to: today) else { return [] }
        let window = sessions.filter {
            $0.startedAt >= from && $0.startedAt < today && Self.hasCompletedWork($0)
        }
        return Dictionary(grouping: window) { cal.startOfDay(for: $0.startedAt) }
            .map { (day: $0.key, sessions: $0.value.sorted { $0.startedAt > $1.startedAt }) }
            .sorted { $0.day > $1.day }
    }

    /// One session row, swipe-deletable.
    ///
    /// `swipeActions` rather than `onDelete`: the rows are nested inside a
    /// per-day `ForEach` now, where `onDelete`'s offsets are relative to the
    /// inner collection and easy to apply to the wrong array. This deletes the
    /// session it is attached to and cannot drift.
    @ViewBuilder
    private func sessionRow(_ session: TrainingSession) -> some View {
        Button { activeSession = session } label: {
            SessionRow(session: session, exercises: exercises, showsDate: false)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                context.delete(session)
                saveChanges()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    /// Cardio ACWR, or nil when too few workouts carry heart rate to answer.
    private var cardioLoad: CardioLoadAnalyzer.Result? {
        guard let profile = profiles.first,
              let restingHR = vitals.compactMap(\.restingHR).first
        else { return nil }
        let records = loadWorkouts
            .filter { !$0.activity.isStrength }
            .map { CardioRecord(date: $0.startedAt,
                                durationMinutes: $0.durationSeconds / 60,
                                avgHeartRate: $0.avgHeartRate) }
        return CardioLoadAnalyzer().acwr(records: records,
                                         restingHR: restingHR,
                                         age: Double(profile.ageYears),
                                         isFemale: profile.sex == .female)
    }

    private var progressions: [ExerciseProgression] {
        let window = DateInterval(start: .now.addingTimeInterval(-60 * 86_400), end: .now)
        return ProgressionAnalyzer().progressions(records: allRecords, window: window)
    }

    /// Top gainers *and* anything going backwards. The list is sorted by change
    /// descending, so a plain `prefix` would hide every regression once more
    /// than a handful of lifts are tracked — losing exactly the lifts worth
    /// acting on.
    ///
    /// Takes the list rather than reading `progressions`, which re-runs the
    /// analyser over every record each time it is touched — and this function
    /// touched it five times.
    private func shownProgressions(_ all: [ExerciseProgression]) -> [ExerciseProgression] {
        guard all.count > 6 else { return all }
        let declining = all.filter { $0.change < 0 }
        let gaining = all.filter { $0.change >= 0 }
        return Array(gaining.prefix(4)) + Array(declining.suffix(3))
    }

    var body: some View {
        // Both walk the whole training history, and everything below reads them
        // several times over. Once per redraw, not once per reader.
        let volume = thisWeekVolume
        let progress = progressions
        NavigationStack {
            List {
                Group {
                Section {
                    Button { showingPicker = true } label: {
                        Label("New workout", systemImage: "plus.circle.fill")
                            .font(.headline)
                    }
                } header: {
                    FeatureCategoryBar("Workout")
                } footer: {
                    if savedTemplates.isEmpty {
                        Text("Pick any activity — gym, run, ride, swim — or import "
                             + "one your watch already recorded.")
                    }
                }

                watchSection

                Section {
                    if todaySessions.isEmpty {
                        Text("Nothing logged yet today.").foregroundStyle(Theme.textSecondary)
                    }
                    ForEach(todaySessions) { session in
                        sessionRow(session)
                    }
                } header: {
                    FeatureCategoryBar("Today")
                }

                Section {
                    if recentSessionDays.isEmpty {
                        Text("No gym workouts in the last week.").foregroundStyle(Theme.textSecondary)
                    }
                    ForEach(recentSessionDays, id: \.day) { group in
                        Text(group.day, format: .dateTime.weekday(.wide).day().month())
                            .font(Theme.text(13, .semibold))
                            .foregroundStyle(Theme.textSecondary)
                            .listRowBackground(Color.clear)
                            .listRowInsets(.init(top: 10, leading: 20, bottom: 2, trailing: 20))
                        ForEach(group.sessions) { session in
                            sessionRow(session)
                        }
                    }
                } header: {
                    FeatureCategoryBar("Last 7 days")
                }

                Section {
                    // Tall enough that width, not height, is the binding
                    // constraint — otherwise the pair is letterboxed and the
                    // hands stop short of the card edges.
                    // `rank` decides which muscle gives a shared region its
                    // colour — the mid and lower traps are one shape here, and
                    // the busier of the two should win rather than whichever
                    // happens to be listed first.
                    MuscleMap(figure: BodyArt.figure(for: profiles.first?.sex ?? .other),
                              untrained: MuscleVolumeScale.untrained,
                              rank: { volume[$0]?.effective ?? 0 },
                              colour: { MuscleVolumeScale.colour(for: volume[$0], muscle: $0) })
                        .frame(height: 340)
                        .padding(.vertical, 4)
                        .listRowInsets(.init(top: 6, leading: 6, bottom: 6, trailing: 6))

                    overallBand(volume)

                    Button { showingMuscleBreakdown = true } label: {
                        HStack(spacing: 10) {
                            Label("View muscle breakdown", systemImage: "list.bullet")
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                            Text("\(trainedMuscleCount(volume)) trained")
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.gold)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Shows every muscle and its sets for this week")
                } header: {
                    FeatureCategoryBar("Muscles worked this week")
                }

                if !progress.isEmpty {
                    Section {
                        ForEach(shownProgressions(progress), id: \.exerciseID) { p in
                            HStack {
                                Text(exercises.first { $0.id == p.exerciseID }?.name ?? "Exercise")
                                Spacer()
                                Text("\(Int(units.displayWeight(p.currentE1RM))) \(units.weightUnit) e1RM")
                                    .font(.caption).foregroundStyle(Theme.textSecondary)
                                Text(p.change, format: .percent.precision(.fractionLength(0...1)).sign(strategy: .always()))
                                    .monospacedDigit()
                                    .foregroundStyle(p.change >= 0 ? .green : .orange)
                            }
                        }
                    } header: {
                        FeatureCategoryBar("Strength — last 60 days")
                    }
                }

                Section {
                    NavigationLink {
                        ExerciseProgressView()
                    } label: {
                        Label("Weight progress", systemImage: "chart.xyaxis.line")
                            .foregroundStyle(Theme.gold)
                    }
                } header: {
                    FeatureCategoryBar("Progress")
                }

                if let load = cardioLoad {
                    Section {
                        HStack {
                            Text("Cardio load")
                            Spacer()
                            Text(String(format: "%.2f", load.ratio))
                                .monospacedDigit()
                            Text(load.band.rawValue)
                                .font(.caption)
                                .foregroundStyle(bandColor(load.band))
                        }
                    } header: {
                        FeatureCategoryBar("Cardio load")
                    } footer: {
                        Text("Acute:chronic ratio for cardio only, from heart-rate "
                             + "load. Reported separately from lifting — the two "
                             + "have no shared unit — and not folded into your "
                             + "recovery score.")
                    }
                }

                if !displayedWorkouts.isEmpty {
                    Section {
                        ForEach(displayedWorkouts.prefix(30)) { workout in
                            Button { detailWorkout = workout } label: {
                                WorkoutRow(workout: workout, units: units)
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete { offsets in
                            let shown = Array(displayedWorkouts.prefix(30))
                            for i in offsets { context.delete(shown[i]) }
                            saveChanges()
                        }
                    } header: {
                        FeatureCategoryBar("Activities")
                    }
                }
                }
                .listRowBackground(Theme.surface)
            }
            .navigationTitle("Train")
            .themedChrome()
            .navigationBarTitleDisplayMode(.inline)
            .featureList()
            .settingsToolbar()
            .task {
                ExerciseLibrary.seedIfNeeded(context: context)
                await watch.start()
                await WorkoutSyncService(context: context).sync()
            }
            .fullScreenCover(item: $activeSession) { session in
                ActiveWorkoutView(session: session)
            }
            .fullScreenCover(item: $liveActivity) { activity in
                LiveCardioView(activity: activity)
            }
            .sheet(item: $detailWorkout) { workout in
                WorkoutDetailView(workout: workout)
            }
            .sheet(isPresented: $showingMuscleBreakdown) {
                muscleBreakdownSheet(volume)
            }
            .sheet(isPresented: $showingPicker) {
                ActivityPickerView(
                    recentWatchWorkouts: unimportedWatchWorkouts,
                    onStartStrength: { start(template: $0) },
                    onStartLive: { liveActivity = $0 },
                    onImport: { sample in
                        WorkoutSyncService(context: context).apply([sample])
                        saveChanges()
                    })
            }
            .alert("Couldn't save training data", isPresented: Binding(
                get: { persistenceFailure != nil },
                set: { if !$0 { persistenceFailure = nil } })) {
                Button("OK", role: .cancel) { persistenceFailure = nil }
            } message: {
                Text(persistenceFailure ?? "")
            }
        }
    }

    private func trainedMuscleCount(
        _ volume: [MuscleGroup: VolumeAggregator.EffectiveVolume]
    ) -> Int {
        volume.values.filter { $0.effective > 0 }.count
    }

    private func muscleBreakdownSheet(
        _ volume: [MuscleGroup: VolumeAggregator.EffectiveVolume]
    ) -> some View {
        NavigationStack {
            List { weeklyTable(volume) }
                .navigationTitle("Muscles trained")
                .navigationBarTitleDisplayMode(.inline)
                .themedChrome()
                .featureList(bottomPadding: 24)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { showingMuscleBreakdown = false }
                    }
                    .withoutGlassBackground()
                }
        }
        .presentationDetents([.large])
    }

    /// Watch workouts that aren't already stored, so the picker never offers to
    /// import something twice.
    private var unimportedWatchWorkouts: [WorkoutSample] {
        let stored = Set((workouts + loadWorkouts).compactMap(\.externalID))
        return watch.todaysWorkouts.filter { !stored.contains($0.externalID) }
    }

    @ViewBuilder
    private var watchSection: some View {
        if let live = watch.liveWorkout {
            Section {
                HStack {
                    Image(systemName: "applewatch.radiowaves.left.and.right")
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(live.activityName) in progress")
                            .font(.subheadline.weight(.medium))
                        Text(live.startedAt, style: .timer)
                            .font(.caption).monospacedDigit().foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    if let hr = live.heartRate {
                        Label("\(Int(hr))", systemImage: "heart.fill")
                            .font(.subheadline).foregroundStyle(.red).monospacedDigit()
                    }
                }
            } header: {
                FeatureCategoryBar("On your watch")
            }
        } else if !unimportedWatchWorkouts.isEmpty {
            Section {
                ForEach(unimportedWatchWorkouts, id: \.externalID) { w in
                    HStack {
                        Image(systemName: w.activity.symbolName)
                        Text(w.activity.displayName)
                        Spacer()
                        Text("\(Int(w.durationSeconds / 60)) min · \(Int(w.activeEnergyKcal)) kcal")
                            .font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                }
            } header: {
                FeatureCategoryBar("Today from Apple Watch")
            }
        }
    }

    private func bandColor(_ band: CardioLoadAnalyzer.Result.Band) -> Color {
        switch band {
        case .optimal: return .green
        case .detraining: return .secondary
        case .elevated: return .orange
        case .spike: return .red
        }
    }

    /// The whole body's week in one box.
    ///
    /// The diagram shows where the work went; this says whether there was
    /// enough of it. Deliberately just a colour and a word — the thresholds
    /// behind it differ per muscle, and spelling that out here would be a
    /// paragraph nobody reads under a picture that already made the point.
    private func overallBand(_ volume: [MuscleGroup: VolumeAggregator.EffectiveVolume])
        -> some View {
        let band = MuscleVolumeScale.overall(volume)
        return Text(band.title)
            .font(Theme.text(15, .semibold))
            .foregroundStyle(band.colour)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                    .fill(band.colour.opacity(0.16))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                    .strokeBorder(band.colour.opacity(0.45), lineWidth: 1)
            )
            .listRowInsets(.init(top: 2, leading: 12, bottom: 10, trailing: 12))
    }

    /// Every muscle group and what it got this week, sortable and searchable.
    private func weeklyTable(_ volume: [MuscleGroup: VolumeAggregator.EffectiveVolume])
        -> some View {
        let rows = weeklyRows(volume)
        return Section {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Theme.textSecondary)
                TextField("Search muscles", text: $muscleQuery)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if !muscleQuery.isEmpty {
                    Button { muscleQuery = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            if rows.isEmpty {
                Text("No muscle matches \"\(muscleQuery)\".")
                    .foregroundStyle(Theme.textSecondary)
            }
            ForEach(rows) { row in
                HStack {
                    Text(row.muscle.displayName)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    // A separate, quieter label rather than a longer string:
                    // "Triceps lateral head" beside "3 sets (secondary)" runs
                    // out of row on a small phone.
                    if row.isSecondaryOnly {
                        Text("secondary")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Text(setsLabel(row))
                        .monospacedDigit()
                        .foregroundStyle(rowColour(row))
                }
            }
        } header: {
            HStack {
                Text("This week")
                Spacer()
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { leastTrainedFirst.toggle() }
                } label: {
                    Label(leastTrainedFirst ? "Least trained first" : "Most trained first",
                          systemImage: leastTrainedFirst ? "arrow.up" : "arrow.down")
                        .labelStyle(.iconOnly)
                        .font(.footnote.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.gold)
                .accessibilityLabel(leastTrainedFirst
                                    ? "Sorting least trained first. Tap to reverse."
                                    : "Sorting most trained first. Tap to reverse.")
            }
        } footer: {
            Text("A set counts when the lift actually targets the muscle. Work "
                 + "that only assists — the lower back in a squat, the forearms "
                 + "in a deadlift — is marked secondary, and still counts "
                 + "towards the colour and the ordering.")
        }
    }

    /// Whole sets, of whichever kind the row has.
    ///
    /// A dash now means genuinely untouched, and nothing else. It used to also
    /// mean "worked, but never hard enough to count", which put "—" beside a
    /// muscle the diagram directly above had coloured in.
    private func setsLabel(_ row: MuscleRow) -> String {
        switch row.displayedSets {
        case 0:  return "—"
        case 1:  return "1 set"
        default: return "\(row.displayedSets) sets"
        }
    }

    /// The row's text colour, on exactly the diagram's scale.
    ///
    /// One function, one answer: the number in the table and the shade on the
    /// figure above it now come from the same call, so they cannot disagree.
    ///
    /// `.secondary` stands in for an untrained muscle — the scale's own grey is
    /// a fill colour for the body map and would be all but invisible as text.
    private func rowColour(_ row: MuscleRow) -> Color {
        guard row.volume != nil else { return .secondary }
        let colour = MuscleVolumeScale.colour(for: row.volume, muscle: row.muscle)
        return colour == MuscleVolumeScale.untrained ? .secondary : colour
    }

    private func start(template: WorkoutTemplate?) {
        let repeated: [TrainingRecords.PlannedSet]
        do {
            repeated = try template.map {
                TrainingRecords.repeatedPlan(
                    templateName: $0.name,
                    exerciseIDs: $0.orderedExerciseIDs,
                    sessions: try TrainingSessionRepository.repeatCandidates(for: $0,
                                                                              context: context))
            } ?? []
        } catch {
            persistenceFailure = "Loading saved workout: \(error.localizedDescription)"
            return
        }
        let session = TrainingSession(templateName: template?.name)
        context.insert(session)
        for planned in repeated {
            let entry = SetEntry(order: planned.order,
                                 exerciseID: planned.exerciseID,
                                 weightKg: planned.weightKg,
                                 reps: planned.reps)
            entry.rir = planned.rir
            entry.restSeconds = planned.restSeconds
            entry.isWarmup = planned.isWarmup
            entry.completedAt = nil
            entry.session = session
            context.insert(entry)
        }
        if saveChanges() { activeSession = session }
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
