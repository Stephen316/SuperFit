import SwiftUI
import SwiftData
import Charts

/// Per-exercise strength history: the heaviest working set of each session, over
/// a selectable 1 / 3 / 6-month window. One chart per exercise, most recently
/// trained first, so the whole logged history reads top to bottom.
struct ExerciseProgressView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @AppStorage(UnitSystem.storageKey) private var unitsRaw = UnitSystem.metric.rawValue
    @State private var range: LiftRange = .oneMonth

    /// Nil is the existing all-exercise screen. A value turns the same charts
    /// into a muscle drill-down and adds every direct and assisting set below.
    let muscle: MuscleGroup?

    init(muscle: MuscleGroup? = nil) {
        self.muscle = muscle
    }

    private var units: UnitSystem { UnitSystem(rawValue: unitsRaw) ?? .metric }

    private var exerciseName: [UUID: String] {
        Dictionary(exercises.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
    }

    private var exerciseTensions: [UUID: [MuscleGroup: Int]] {
        Dictionary(exercises.map { ($0.id, $0.tension) }, uniquingKeysWith: { a, _ in a })
    }

    private struct ProgressData {
        let series: [LiftProgressSeries]
        let affectingSets: [LiftRecord]
        let loadError: String?
    }

    private var progressData: ProgressData {
        // Fetch only the window the range needs: the fixed ranges stay bounded,
        // all-time deliberately pulls the whole logged history.
        let cutoff = range.start
        let descriptor = FetchDescriptor<TrainingSession>(
            predicate: #Predicate { $0.startedAt >= cutoff },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
        do {
            let sessions = try context.fetch(descriptor)
            let fractions = Dictionary(exercises.map { ($0.id, $0.bodyweightFraction) },
                                       uniquingKeysWith: { a, _ in a })
            let allRecords = TrainingRecords.completed(sessions, fractions: fractions)
            let records = muscle.map {
                MuscleProgress.affectingSets($0, records: allRecords,
                                             tensions: exerciseTensions)
            } ?? allRecords
            return ProgressData(
                series: LiftProgress.downsampledSeries(records: records, since: cutoff,
                                                       sampling: range.sampling),
                affectingSets: muscle == nil ? [] : records,
                loadError: nil)
        } catch {
            return ProgressData(series: [], affectingSets: [],
                                loadError: error.localizedDescription)
        }
    }

    var body: some View {
        let data = progressData
        ZStack {
            FeatureBackground()
            ScrollView {
                // Lazy so only the charts scrolled into view are built — a heavy
                // lifter with dozens of exercises pays for what's on screen, not
                // for the whole history at once.
                LazyVStack(spacing: 14) {
                    FeatureTabControl(
                        options: LiftRange.allCases.map { ($0, $0.label) },
                        selection: $range)

                    if let error = data.loadError {
                        emptyState(title: "Couldn't load progress", message: error)
                    } else if let muscle {
                        muscleProgress(data, muscle: muscle)
                    } else if data.series.isEmpty {
                        emptyState(title: "No logged lifts yet",
                                   message: "Complete a weighted working set and it will chart here.")
                    } else {
                        ForEach(data.series) { chart(for: $0) }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle(muscle?.displayName ?? "Weight progress")
        .themedChrome()
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    @ViewBuilder
    private func muscleProgress(_ data: ProgressData, muscle: MuscleGroup) -> some View {
        if data.affectingSets.isEmpty {
            emptyState(
                title: "No sets in this period",
                message: "Completed direct and assisting sets for \(muscle.displayName) will appear here.")
        } else {
            sectionTitle("Weight progress")
            if data.series.isEmpty {
                emptyState(
                    title: "No weighted progress yet",
                    message: "Bodyweight sets are included below. Add external load to create a weight chart.",
                    topPadding: 12)
            } else {
                ForEach(data.series) { chart(for: $0) }
            }

            sectionTitle("All affecting sets", count: data.affectingSets.count)
            ForEach(data.affectingSets.indices, id: \.self) { index in
                affectedSetCard(data.affectingSets[index], muscle: muscle)
            }
        }
    }

    private func sectionTitle(_ title: String, count: Int? = nil) -> some View {
        HStack {
            Text(title)
                .font(Theme.text(15, .semibold))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            if let count {
                Text("\(count) \(count == 1 ? "set" : "sets")")
                    .font(Theme.text(13))
                    .foregroundStyle(Theme.textSecondary)
                    .monospacedDigit()
            }
        }
        .padding(.top, 6)
    }

    private func chart(for s: LiftProgressSeries) -> some View {
        let name = exerciseName[s.exerciseID] ?? "Exercise"
        let delta = (s.latest?.maxWeightKg ?? 0) - (s.earliest?.maxWeightKg ?? 0)
        return HistoryChartCard(
            title: name,
            headline: s.latest.map { units.weightString($0.maxWeightKg) },
            change: s.points.count > 1
                ? String(format: "%+.1f %@", units.displayWeight(delta), units.weightUnit)
                : nil,
            changeIsGood: delta >= 0,
            height: 150,
            yLabel: { "\(Int($0))" },
            content: {
                ForEach(s.points) { p in
                    LineMark(x: .value("Date", p.date),
                             y: .value(units.weightUnit, units.displayWeight(p.maxWeightKg)))
                        .foregroundStyle(Theme.gold)
                        .interpolationMethod(.monotone)
                }
                ForEach(s.points) { p in
                    PointMark(x: .value("Date", p.date),
                              y: .value(units.weightUnit, units.displayWeight(p.maxWeightKg)))
                        .foregroundStyle(Theme.gold)
                        .symbolSize(20)
                }
            },
            isEmpty: s.points.count < 2,
            emptyMessage: "One session so far — log another to see a trend."
        )
    }

    private func affectedSetCard(_ record: LiftRecord, muscle: MuscleGroup) -> some View {
        let score = MuscleProgress.tension(for: record, muscle: muscle,
                                           tensions: exerciseTensions)
        let direct = score >= VolumeAggregator.fullSetTension
        return ThemeCard(padding: 14, radius: Theme.cardRadiusCompact) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(exerciseName[record.exerciseID] ?? "Exercise")
                        .font(Theme.text(15, .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(direct ? "direct" : "secondary")
                        .font(Theme.text(12, .medium))
                        .foregroundStyle(direct ? Theme.gold : Theme.textSecondary)
                }
                HStack(spacing: 7) {
                    Text(record.date, format: .dateTime.day().month().year())
                    Text("·")
                    Text(setSummary(record))
                    Spacer(minLength: 4)
                    Text("Tension \(score)/5")
                }
                .font(Theme.text(13))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
        }
    }

    private func setSummary(_ record: LiftRecord) -> String {
        let load: String
        if record.bodyweightFraction > 0 {
            load = record.weightKg > 0
                ? "Bodyweight + \(units.weightString(record.weightKg))"
                : "Bodyweight"
        } else {
            load = units.weightString(record.weightKg)
        }
        return "\(load) × \(record.reps)"
    }

    private func emptyState(title: String, message: String,
                            topPadding: CGFloat = 48) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(Theme.font(16))
                .foregroundStyle(Theme.textPrimary)
            Text(message)
                .font(Theme.font(13))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, topPadding)
    }
}

/// The windows the strength history offers — the 1 / 3 / 6 months requested.
enum LiftRange: Int, CaseIterable, Identifiable {
    case oneMonth = 30, threeMonths = 90, sixMonths = 180, allTime = 0

    var id: Int { rawValue }
    var label: String {
        switch self {
        case .oneMonth: return "1M"
        case .threeMonths: return "3M"
        case .sixMonths: return "6M"
        case .allTime: return "All"
        }
    }
    /// Start of the window, anchored to the start of the day for stable buckets;
    /// unbounded for all-time.
    var start: Date {
        guard self != .allTime else { return .distantPast }
        return Calendar.current.startOfDay(for: .now).addingTimeInterval(-Double(rawValue) * 86_400)
    }
    /// Monthly bests over the whole history for all-time; age-tiered otherwise.
    var sampling: LiftProgress.Sampling { self == .allTime ? .monthly : .aged }
}
