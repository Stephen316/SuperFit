import SwiftUI
import SwiftData

struct TrainingView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \TrainingSession.startedAt, order: .reverse) private var sessions: [TrainingSession]
    @Query private var exercises: [Exercise]

    @State private var activeSession: TrainingSession?

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
        let muscles = Dictionary(uniqueKeysWithValues: exercises.map { ($0.id, $0.muscles) })
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
                        ForEach(ExerciseLibrary.templates, id: \.name) { template in
                            Button(template.name) { start(template: template) }
                        }
                        Divider()
                        Button("Empty workout") { start(template: nil) }
                    } label: {
                        Label("Start workout", systemImage: "plus.circle.fill")
                            .font(.headline)
                    }
                }

                if !thisWeekVolume.isEmpty {
                    Section("This week — sets per muscle") {
                        ForEach(thisWeekVolume.sorted { $0.value > $1.value }, id: \.key) { muscle, sets in
                            HStack {
                                Text(muscle.rawValue.capitalized)
                                Spacer()
                                Text(sets.formatted(.number.precision(.fractionLength(0...1))))
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
            .task { ExerciseLibrary.seedIfNeeded(context: context) }
            .fullScreenCover(item: $activeSession) { session in
                ActiveWorkoutView(session: session)
            }
        }
    }

    private func volumeColor(_ sets: Double) -> Color {
        let range = VolumeAggregator.weeklySetTargets
        if sets < range.lowerBound { return .secondary }
        if sets > range.upperBound { return .orange }
        return .green
    }

    private func start(template: (name: String, exercises: [String])?) {
        let session = TrainingSession(templateName: template?.name)
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
