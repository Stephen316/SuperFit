import SwiftUI
import SwiftData

struct TrainingView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \TrainingSession.startedAt, order: .reverse) private var sessions: [TrainingSession]
    @Query private var exercises: [Exercise]
    @Query(sort: \WorkoutTemplate.createdAt, order: .reverse) private var savedTemplates: [WorkoutTemplate]

    @Query(sort: \WorkoutRecord.startedAt, order: .reverse) private var workouts: [WorkoutRecord]
    @Query private var profiles: [UserProfile]
    @Query(sort: \DailyVitals.date, order: .reverse) private var vitals: [DailyVitals]

    @State private var activeSession: TrainingSession?
    @State private var watch = WatchWorkoutMonitor()
    @State private var showingPicker = false
    @State private var muscleQuery = ""
    @State private var leastTrainedFirst = false
    @State private var liveActivity: WorkoutActivity?
    @State private var detailWorkout: WorkoutRecord?
    @AppStorage(UnitSystem.storageKey) private var unitsRaw = UnitSystem.metric.rawValue

    private var units: UnitSystem { UnitSystem(rawValue: unitsRaw) ?? .metric }

    private var allRecords: [LiftRecord] {
        let fractions = Dictionary(exercises.map { ($0.id, $0.bodyweightFraction) },
                                   uniquingKeysWith: { a, _ in a })
        return sessions.flatMap { s in
            (s.sets ?? []).compactMap { set -> LiftRecord? in
                guard let id = set.exerciseID else { return nil }
                return LiftRecord(date: s.startedAt, exerciseID: id,
                                  weightKg: set.weightKg, reps: set.reps,
                                  isWarmup: set.isWarmup,
                                  bodyweightFraction: fractions[id] ?? 0)
            }
        }
    }

    /// One row of the weekly table.
    ///
    /// Three numbers because they answer three different questions, and
    /// collapsing them loses one. `sets` is what a person did — two sets are two
    /// sets. `secondary` is work the muscle took without being the point of the
    /// exercise. `weighted` knows a chin-up is worth more to the lats than to
    /// the abs, which is the ordering worth seeing, and it separates rows that
    /// would otherwise tie at the same whole number.
    private struct MuscleRow: Identifiable {
        let muscle: MuscleGroup
        /// Sets that targeted this muscle — tension at or above `fullSetTension`.
        let sets: Int
        /// Sets that involved it without targeting it.
        let secondary: Int
        /// Tension-weighted total. Sorts and colours; never shown as a number.
        let weighted: Double

        var id: MuscleGroup { muscle }

        /// Worked, but never as the target. The lower back after a week of
        /// squats. Shown with its own count and a qualifier rather than the
        /// dash it used to get, which contradicted the coloured diagram above.
        var isSecondaryOnly: Bool { sets == 0 && secondary > 0 }

        /// The number the row prints, whichever kind of set it is.
        var displayedSets: Int { sets > 0 ? sets : secondary }
    }

    /// Rows for the weekly table: every group, whether trained or not.
    ///
    /// Including the untrained ones is the point — "least trained first" is
    /// meaningless if a muscle you never touched simply isn't in the list, and
    /// the gap is what the table exists to show.
    private var weeklyRows: [MuscleRow] {
        let volume = thisWeekVolume
        let counts = thisWeekSetCounts
        let secondary = thisWeekSecondaryCounts
        let term = muscleQuery.trimmingCharacters(in: .whitespaces)
        return MuscleGroup.allCases
            .map { MuscleRow(muscle: $0, sets: counts[$0] ?? 0,
                             secondary: secondary[$0] ?? 0, weighted: volume[$0] ?? 0) }
            .filter { term.isEmpty || $0.muscle.displayName.localizedCaseInsensitiveContains(term) }
            .sorted { a, b in
                // Alphabetical tiebreak so the many zero rows keep a stable,
                // findable order instead of shuffling on every redraw.
                if a.weighted != b.weighted {
                    return leastTrainedFirst ? a.weighted < b.weighted : a.weighted > b.weighted
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

    private var thisWeekSetCounts: [MuscleGroup: Int] {
        guard let week = currentWeek else { return [:] }
        return VolumeAggregator().weeklySetCounts(records: allRecords,
                                                  muscles: muscleTension, week: week)
    }

    private var thisWeekSecondaryCounts: [MuscleGroup: Int] {
        guard let week = currentWeek else { return [:] }
        return VolumeAggregator().weeklySecondarySetCounts(records: allRecords,
                                                           muscles: muscleTension, week: week)
    }

    private var thisWeekVolume: [MuscleGroup: Double] {
        guard let week = currentWeek else { return [:] }
        return VolumeAggregator().weeklySets(records: allRecords,
                                             muscles: muscleTension, week: week)
    }

    /// Cardio ACWR, or nil when too few workouts carry heart rate to answer.
    private var cardioLoad: CardioLoadAnalyzer.Result? {
        guard let profile = profiles.first,
              let restingHR = vitals.compactMap(\.restingHR).first
        else { return nil }
        let records = workouts
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

    /// Top gainers *and* anything going backwards. `progressions` is sorted by
    /// change descending, so a plain `prefix` would hide every regression once
    /// more than a handful of lifts are tracked — losing exactly the lifts worth
    /// acting on.
    private var shownProgressions: [ExerciseProgression] {
        guard progressions.count > 6 else { return progressions }
        let declining = progressions.filter { $0.change < 0 }
        let gaining = progressions.filter { $0.change >= 0 }
        return Array(gaining.prefix(4)) + Array(declining.suffix(3))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { showingPicker = true } label: {
                        Label("New workout", systemImage: "plus.circle.fill")
                            .font(.headline)
                    }
                } footer: {
                    if savedTemplates.isEmpty {
                        Text("Pick any activity — gym, run, ride, swim — or import "
                             + "one your watch already recorded.")
                    }
                }

                watchSection

                Section("Muscles worked this week") {
                    // Tall enough that width, not height, is the binding
                    // constraint — otherwise the pair is letterboxed and the
                    // hands stop short of the card edges.
                    // `rank` decides which muscle gives a shared region its
                    // colour — the mid and lower traps are one shape here, and
                    // the busier of the two should win rather than whichever
                    // happens to be listed first.
                    MuscleMap(figure: BodyArt.figure(for: profiles.first?.sex ?? .other),
                              untrained: MuscleVolumeScale.untrained,
                              rank: { thisWeekVolume[$0] ?? 0 },
                              colour: { MuscleVolumeScale.colour(forWeightedSets: thisWeekVolume[$0] ?? 0) })
                        .frame(height: 340)
                        .padding(.vertical, 4)
                        .listRowInsets(.init(top: 6, leading: 6, bottom: 6, trailing: 6))
                }

                weeklyTable

                if !progressions.isEmpty {
                    Section("Strength — last 60 days") {
                        ForEach(shownProgressions, id: \.exerciseID) { p in
                            HStack {
                                Text(exercises.first { $0.id == p.exerciseID }?.name ?? "Exercise")
                                Spacer()
                                Text("\(Int(units.displayWeight(p.currentE1RM))) \(units.weightUnit) e1RM")
                                    .font(.caption).foregroundStyle(.secondary)
                                Text(p.change, format: .percent.precision(.fractionLength(0...1)).sign(strategy: .always()))
                                    .monospacedDigit()
                                    .foregroundStyle(p.change >= 0 ? .green : .orange)
                            }
                        }
                    }
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
                    } footer: {
                        Text("Acute:chronic ratio for cardio only, from heart-rate "
                             + "load. Reported separately from lifting — the two "
                             + "have no shared unit — and not folded into your "
                             + "recovery score.")
                    }
                }

                if !workouts.isEmpty {
                    Section("Activities") {
                        ForEach(workouts.prefix(30)) { workout in
                            Button { detailWorkout = workout } label: {
                                WorkoutRow(workout: workout, units: units)
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete { offsets in
                            let shown = Array(workouts.prefix(30))
                            for i in offsets { context.delete(shown[i]) }
                            try? context.save()
                        }
                    }
                }

                Section("Gym history") {
                    if sessions.isEmpty {
                        Text("No gym workouts yet.").foregroundStyle(.secondary)
                    }
                    ForEach(sessions.prefix(30)) { session in
                        Button { activeSession = session } label: {
                            SessionRow(session: session, exercises: exercises)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { offsets in
                        for i in offsets { context.delete(sessions[i]) }
                        try? context.save()
                    }
                }
            }
            .navigationTitle("Train")
            .themedChrome()
            .navigationBarTitleDisplayMode(.inline)
            .themedList()
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
            .sheet(isPresented: $showingPicker) {
                ActivityPickerView(
                    savedTemplates: savedTemplates,
                    recentWatchWorkouts: unimportedWatchWorkouts,
                    onStartStrength: { start(named: $0) },
                    onStartLive: { liveActivity = $0 },
                    onImport: { sample in
                        WorkoutSyncService(context: context).apply([sample])
                        try? context.save()
                    })
            }
        }
    }

    /// Watch workouts that aren't already stored, so the picker never offers to
    /// import something twice.
    private var unimportedWatchWorkouts: [WorkoutSample] {
        let stored = Set(workouts.compactMap(\.externalID))
        return watch.todaysWorkouts.filter { !stored.contains($0.externalID) }
    }

    @ViewBuilder
    private var watchSection: some View {
        if let live = watch.liveWorkout {
            Section("On your watch") {
                HStack {
                    Image(systemName: "applewatch.radiowaves.left.and.right")
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(live.activityName) in progress")
                            .font(.subheadline.weight(.medium))
                        Text(live.startedAt, style: .timer)
                            .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let hr = live.heartRate {
                        Label("\(Int(hr))", systemImage: "heart.fill")
                            .font(.subheadline).foregroundStyle(.red).monospacedDigit()
                    }
                }
            }
        } else if !watch.todaysWorkouts.isEmpty {
            Section("Today from Apple Watch") {
                ForEach(watch.todaysWorkouts, id: \.externalID) { w in
                    HStack {
                        Image(systemName: w.activity.symbolName)
                        Text(w.activity.displayName)
                        Spacer()
                        Text("\(Int(w.durationSeconds / 60)) min · \(Int(w.activeEnergyKcal)) kcal")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
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

    /// Every muscle group and what it got this week, sortable and searchable.
    private var weeklyTable: some View {
        Section {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search muscles", text: $muscleQuery)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if !muscleQuery.isEmpty {
                    Button { muscleQuery = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            if weeklyRows.isEmpty {
                Text("No muscle matches \"\(muscleQuery)\".")
                    .foregroundStyle(.secondary)
            }
            ForEach(weeklyRows) { row in
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
                            .foregroundStyle(.secondary)
                    }
                    Text(setsLabel(row))
                        .monospacedDigit()
                        .foregroundStyle(row.sets == 0 ? .secondary : volumeColor(row.weighted))
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

    /// Bands the weighted total, not the count beside it.
    ///
    /// The two answer different questions. The number says how many sets you
    /// put in — a tally you can check against what you remember doing. The
    /// colour says how much stimulus the muscle actually took, where three sets
    /// of bench mean more to the chest than to the front delts that shared
    /// them. Banding the count instead would paint both the same.
    ///
    /// On the diagram's scale, not a second one. This used to band on
    /// `weeklySetTargets` (10–20), so a muscle at 4 weighted sets was green on
    /// the figure and grey in the table directly beneath it. One scale, one
    /// answer.
    ///
    /// `.secondary` stands in below the floor: the scale's own `untrained` is a
    /// fill colour for the body map and would be all but invisible as text.
    private func volumeColor(_ sets: Double) -> Color {
        sets > MuscleVolumeScale.minimumTrained
            ? MuscleVolumeScale.colour(forWeightedSets: sets)
            : .secondary
    }

    private func start(named templateName: String?) {
        let session = TrainingSession(templateName: templateName)
        context.insert(session)
        try? context.save()
        activeSession = session
    }
}

struct WorkoutRow: View {
    let workout: WorkoutRecord
    let units: UnitSystem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: workout.activity.symbolName)
                .foregroundStyle(Theme.gold)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(workout.activity.displayName)
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text(workout.startedAt, format: .dateTime.month().day())
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text(summary)
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var summary: String {
        var parts = ["\(Int(workout.durationSeconds / 60)) min"]
        if workout.activity.metrics.contains(.distance),
           let metres = workout.distanceMetres, metres > 0 {
            parts.append(units == .metric
                         ? String(format: "%.2f km", metres / 1000)
                         : String(format: "%.2f mi", metres / 1609.344))
        }
        if workout.activeEnergyKcal > 0 {
            parts.append("\(Int(workout.activeEnergyKcal)) kcal")
        }
        if let hr = workout.avgHeartRate { parts.append("\(Int(hr)) bpm") }
        return parts.joined(separator: " · ")
    }
}

struct SessionRow: View {
    let session: TrainingSession
    let exercises: [Exercise]

    @AppStorage(UnitSystem.storageKey) private var unitsRaw = UnitSystem.metric.rawValue

    private var units: UnitSystem { UnitSystem(rawValue: unitsRaw) ?? .metric }
    private var workingSets: [SetEntry] { (session.sets ?? []).filter { !$0.isWarmup } }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(session.templateName ?? "Workout").font(.subheadline.weight(.medium))
                Spacer()
                Text(session.startedAt, format: .dateTime.month().day())
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(summary)
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var summary: String {
        let tonnage = workingSets.reduce(0) { $0 + $1.volumeKg }
        let names = Set(workingSets.compactMap { set in
            exercises.first { $0.id == set.exerciseID }?.name
        })
        let list = names.prefix(3).joined(separator: ", ")
        return "\(workingSets.count) sets · \(Int(units.displayWeight(tonnage))) \(units.weightUnit) total"
            + (list.isEmpty ? "" : " · \(list)")
    }
}
