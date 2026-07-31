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

    private var thisWeekVolume: [MuscleGroup: Double] {
        let cal = Calendar(identifier: .iso8601)
        guard let week = cal.dateInterval(of: .weekOfYear, for: .now) else { return [:] }
        let muscles = Dictionary(uniqueKeysWithValues: exercises.map { ($0.id, $0.tension) })
        return VolumeAggregator().weeklySets(records: allRecords, muscles: muscles, week: week)
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
                    // Every muscle is individually colourable; the mapping from
                    // weekly volume to a shade is deliberately not wired yet, so
                    // for now the figure shows the anatomy and nothing more.
                    MuscleMap()
                        .frame(height: 260)
                        .padding(.vertical, 6)
                }

                if !thisWeekVolume.isEmpty {
                    Section("This week — sets per muscle") {
                        ForEach(thisWeekVolume.sorted { $0.value > $1.value }, id: \.key) { muscle, sets in
                            HStack {
                                Text(muscle.displayName)
                                Spacer()
                                Text("\(Int(sets.rounded())) sets")
                                    .monospacedDigit()
                                    .foregroundStyle(volumeColor(sets))
                            }
                        }
                    }
                }

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

    private func volumeColor(_ sets: Double) -> Color {
        let range = VolumeAggregator.weeklySetTargets
        if sets < range.lowerBound { return .secondary }
        if sets > range.upperBound { return .orange }
        return .green
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
