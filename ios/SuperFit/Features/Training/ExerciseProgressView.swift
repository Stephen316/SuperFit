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

    private var units: UnitSystem { UnitSystem(rawValue: unitsRaw) ?? .metric }

    private var exerciseName: [UUID: String] {
        Dictionary(exercises.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
    }

    private var series: [LiftProgressSeries] {
        // Fetch only the window the range needs: the fixed ranges stay bounded,
        // all-time deliberately pulls the whole logged history.
        let cutoff = range.start
        let descriptor = FetchDescriptor<TrainingSession>(
            predicate: #Predicate { $0.startedAt >= cutoff },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
        let sessions = (try? context.fetch(descriptor)) ?? []
        let fractions = Dictionary(exercises.map { ($0.id, $0.bodyweightFraction) },
                                   uniquingKeysWith: { a, _ in a })
        let records = TrainingRecords.completed(sessions, fractions: fractions)
        return LiftProgress.downsampledSeries(records: records, since: cutoff,
                                              sampling: range.sampling)
    }

    var body: some View {
        let data = series
        return ZStack {
            Theme.background
            ScrollView {
                // Lazy so only the charts scrolled into view are built — a heavy
                // lifter with dozens of exercises pays for what's on screen, not
                // for the whole history at once.
                LazyVStack(spacing: 14) {
                    Picker("Range", selection: $range) {
                        ForEach(LiftRange.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .tint(Theme.gold)

                    if data.isEmpty {
                        emptyState
                    } else {
                        ForEach(data) { chart(for: $0) }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Weight progress")
        .themedChrome()
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
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

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("No logged lifts yet")
                .font(Theme.font(16))
                .foregroundStyle(Theme.textPrimary)
            Text("Complete a weighted working set and it will chart here.")
                .font(Theme.font(13))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 48)
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
