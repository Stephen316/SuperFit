import SwiftUI
import SwiftData

struct TrainingView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \TrainingSession.startedAt, order: .reverse) private var sessions: [TrainingSession]
    @Query private var exercises: [Exercise]
    @Query(sort: \WorkoutTemplate.createdAt, order: .reverse) private var savedTemplates: [WorkoutTemplate]

    @State private var activeSession: TrainingSession?
    @State private var watch = WatchWorkoutMonitor()

    private var allRecords: [LiftRecord] {
        sessions.flatMap { s in
            (s.sets ?? []).compactMap { set -> LiftRecord? in
                guard let id = set.exerciseID else { return nil }
                return LiftRecord(date: s.startedAt, exerciseID: id,
                                  weightKg: set.weightKg, reps: set.reps,
                                  isWarmup: set.isWarmup)
            }
        }
    }

    private var thisWeekVolume: [MuscleGroup: Double] {
        let cal = Calendar(identifier: .iso8601)
        guard let week = cal.dateInterval(of: .weekOfYear, for: .now) else { return [:] }
        let muscles = Dictionary(uniqueKeysWithValues: exercises.map { ($0.id, $0.tension) })
        return VolumeAggregator().weeklySets(records: allRecords, muscles: muscles, week: week)
    }

    private var progressions: [ExerciseProgression] {
        let window = DateInterval(start: .now.addingTimeInterval(-60 * 86_400), end: .now)
        return ProgressionAnalyzer().progressions(records: allRecords, window: window)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Menu {
                        if !savedTemplates.isEmpty {
                            Section("My workouts") {
                                ForEach(savedTemplates) { template in
                                    Button(template.name) { start(named: template.name) }
                                }
                            }
                        }
                        Section("Built-in") {
                            ForEach(ExerciseLibrary.templates, id: \.name) { template in
                                Button(template.name) { start(named: template.name) }
                            }
                        }
                        Divider()
                        Button("Empty workout") { start(named: nil) }
                    } label: {
                        Label("Start workout", systemImage: "plus.circle.fill")
                            .font(.headline)
                    }
                }

                watchSection

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
                        ForEach(progressions.prefix(6), id: \.exerciseID) { p in
                            HStack {
                                Text(exercises.first { $0.id == p.exerciseID }?.name ?? "Exercise")
                                Spacer()
                                Text("\(Int(p.currentE1RM)) kg e1RM")
                                    .font(.caption).foregroundStyle(.secondary)
                                Text(p.change, format: .percent.precision(.fractionLength(0...1)).sign(strategy: .always()))
                                    .monospacedDigit()
                                    .foregroundStyle(p.change >= 0 ? .green : .orange)
                            }
                        }
                    }
                }

                Section("History") {
                    if sessions.isEmpty {
                        Text("No workouts yet.").foregroundStyle(.secondary)
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
            .task {
                ExerciseLibrary.seedIfNeeded(context: context)
                await watch.start()
            }
            .fullScreenCover(item: $activeSession) { session in
                ActiveWorkoutView(session: session)
            }
        }
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
                ForEach(watch.todaysWorkouts.indices, id: \.self) { i in
                    let w = watch.todaysWorkouts[i]
                    HStack {
                        Image(systemName: "applewatch")
                        Text(w.activityName)
                        Spacer()
                        Text("\(Int(w.end.timeIntervalSince(w.start) / 60)) min · \(Int(w.activeEnergyKcal)) kcal")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
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

struct SessionRow: View {
    let session: TrainingSession
    let exercises: [Exercise]

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
        return "\(workingSets.count) sets · \(Int(tonnage)) kg total" + (list.isEmpty ? "" : " · \(list)")
    }
}
