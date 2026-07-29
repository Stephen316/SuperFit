import SwiftUI
import SwiftData
import Charts

/// Daily protein against target over time.
///
/// Total calories decide whether weight moves; protein decides whether what you
/// lose is fat or muscle. It's also the macro people miss most often, so it gets
/// the one adherence view — reached by tapping the protein target rather than
/// living as another card nobody scrolls to.
struct ProteinAdherenceView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(UnitSystem.storageKey) private var unitsRaw = UnitSystem.metric.rawValue

    @Query private var profiles: [UserProfile]
    @Query(sort: \BodyMetrics.date) private var metrics: [BodyMetrics]
    @Query private var logs: [NutritionLog]
    @Query private var energy: [DailyEnergy]
    @Query private var supplements: [Supplement]
    @Query private var supplementEntries: [SupplementEntry]

    @State private var range = HistoryRange.quarter

    private var start: Date { range.start }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background
                ScrollView {
                    VStack(spacing: 14) {
                        Picker("Range", selection: $range) {
                            ForEach(HistoryRange.allCases) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)

                        summaryCard
                        chartCard
                        explanationCard
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Protein")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
        }
    }

    // MARK: - Data

    /// Protein per day from food and supplements, so a shake counts either way.
    private var dailyProtein: [Date: Double] {
        let cal = Calendar.current
        var out: [Date: Double] = [:]
        for log in logs where log.date >= start {
            out[cal.startOfDay(for: log.date), default: 0] += log.proteinG
        }
        for day in out.keys {
            let supplement = SupplementIntake.total(on: day, entries: supplementEntries,
                                                    supplements: supplements)
            if supplement.proteinG > 0 { out[day, default: 0] += supplement.proteinG }
        }
        return out
    }

    /// Target recomputed per day: it tracks bodyweight and the calorie target,
    /// both of which move over a cut, so a fixed line would misreport adherence
    /// at one end of the period or the other.
    private var dailyTarget: [Date: Double] {
        guard let profile = profiles.first else { return [:] }
        let cal = Calendar.current
        let engine = MetabolismEngine()
        let calculator = MacroCalculator()
        let records = MetabolicRecordAssembler.dailyRecords(
            logs: logs, metrics: metrics,
            supplementKcal: SupplementIntake.dailyKcal(
                entries: supplementEntries, supplements: supplements,
                from: start, to: .now))
        let activeEnergy = MetabolicRecordAssembler.avgActiveEnergy(energy: energy)

        var out: [Date: Double] = [:]
        for day in dailyProtein.keys {
            // The weigh-in in force on that day, not today's.
            guard let weight = metrics.last(where: { $0.date <= day }) else { continue }
            let prior = MetabolismEngine.Prior(
                sex: profile.sex, ageYears: profile.ageYears,
                heightCm: profile.heightCm, activity: profile.activity,
                avgActiveEnergyKcal: activeEnergy, leanMassKg: weight.leanMassKg)
            let estimate = engine.estimate(records: records, windowDays: 30,
                                           prior: prior, asOf: day)
            let kcal = engine.calorieTarget(tdee: estimate, goal: profile.goal,
                                            bodyweightKg: weight.basisWeightKg)
            let override = profile.proteinPerKgOverride > 0 ? profile.proteinPerKgOverride : nil
            out[cal.startOfDay(for: day)] = calculator.targets(
                kcal: kcal, goal: profile.goal, bodyweightKg: weight.basisWeightKg,
                leanMassKg: weight.leanMassKg, proteinPerKg: override).proteinG
        }
        return out
    }

    private var points: [HistorySeries.AdherencePoint] {
        HistorySeries.proteinAdherence(dailyProtein: dailyProtein, dailyTarget: dailyTarget)
    }

    // MARK: - Cards

    private var summaryCard: some View {
        let all = points
        let rate = HistorySeries.hitRate(all)
        let average = all.isEmpty ? nil
            : all.reduce(0) { $0 + $1.actual } / Double(all.count)
        let target = all.last?.target

        return HStack(spacing: 0) {
            stat("Days on target", rate.map { "\(Int(($0 * 100).rounded()))%" } ?? "—")
            Rectangle().fill(Theme.divider).frame(width: 1, height: 44)
            stat("Daily average", average.map { "\(Int($0.rounded())) g" } ?? "—")
            Rectangle().fill(Theme.divider).frame(width: 1, height: 44)
            stat("Target now", target.map { "\(Int($0.rounded())) g" } ?? "—")
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .stroke(Theme.hairline, lineWidth: 1)
        )
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(Theme.font(22))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
            Text(label)
                .font(Theme.font(12))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var chartCard: some View {
        let all = points
        return HistoryChartCard(
            title: "Protein vs target",
            height: 190,
            yLabel: { "\(Int($0))g" },
            content: {
                // Bars coloured by whether the day landed, so the pattern of
                // misses is readable without reading any numbers.
                ForEach(all) { point in
                    BarMark(x: .value("Date", point.date, unit: .day),
                            y: .value("Protein", point.actual))
                        .foregroundStyle(point.hit
                                         ? Theme.gold.opacity(0.75)
                                         : Color.orange.opacity(0.55))
                }
                ForEach(all) { point in
                    LineMark(x: .value("Date", point.date),
                             y: .value("Target", point.target))
                        .foregroundStyle(Theme.textPrimary)
                        .lineStyle(.init(lineWidth: 1.5, dash: [4, 3]))
                        .interpolationMethod(.monotone)
                }
            },
            isEmpty: all.count < 2,
            emptyMessage: "Log a few days of food to see how your protein tracks against target."
        )
    }

    private var explanationCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Why protein")
                .font(Theme.font(15))
                .foregroundStyle(Theme.textSecondary)
            Text(explanation)
                .font(Theme.font(14))
                .foregroundStyle(Theme.textPrimary)
            Text("A day counts as on target within 5% — 143 g against a 150 g target still lands.")
                .font(Theme.font(13))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .stroke(Theme.hairline, lineWidth: 1)
        )
    }

    private var explanation: String {
        let usingLean = metrics.last?.leanMassKg != nil
        let basis = usingLean ? "lean mass" : "bodyweight"
        switch profiles.first?.goal {
        case .fatLoss, .recomposition:
            return "In a deficit, protein is what decides whether the weight you lose is fat or muscle. Your target is set from your \(basis) and moves with it."
        case .muscleGain:
            return "Protein supplies the material for new muscle; the surplus supplies the energy. Your target is set from your \(basis)."
        default:
            return "Protein maintains lean mass at any calorie level. Your target is set from your \(basis)."
        }
    }
}
