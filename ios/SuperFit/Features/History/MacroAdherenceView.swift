import SwiftUI
import SwiftData
import Charts

/// The three macros, and the fact that they aren't judged the same way.
enum TrackedMacro: String, CaseIterable, Identifiable, Sendable {
    case protein, carbs, fats
    var id: String { rawValue }

    var title: String { rawValue.capitalized }

    func grams(_ log: NutritionLog) -> Double {
        switch self {
        case .protein: return log.proteinG
        case .carbs:   return log.carbsG
        case .fats:    return log.fatG
        }
    }

    func grams(_ profile: NutrientProfile) -> Double {
        switch self {
        case .protein: return profile.proteinG
        case .carbs:   return profile.carbsG
        case .fats:    return profile.fatG
        }
    }

    func target(_ targets: MacroTargets) -> Double {
        switch self {
        case .protein: return targets.proteinG
        case .carbs:   return targets.carbG
        case .fats:    return targets.fatG
        }
    }

    /// Protein is a floor — going over costs nothing. Carbs and fats are a
    /// budget inside a calorie target, so overshooting is a miss too.
    var rule: HistorySeries.AdherencePoint.Rule {
        self == .protein ? .floor : .band
    }

    var toleranceNote: String {
        switch rule {
        case .floor:
            return "A day counts as on target within 5% — 143 g against a 150 g target still lands."
        case .band:
            return "A day counts within 10% either side. Unlike protein, going well over counts as a miss: these sit inside a calorie target."
        }
    }
}

/// One macro's daily intake against its target over time.
///
/// One view for all three rather than three near-identical files. Protein earns
/// the most attention — it decides whether what you lose is fat or muscle — but
/// carbs and fats are reachable the same way, by tapping their column on the
/// dashboard.
struct MacroAdherenceView: View {
    let macro: TrackedMacro

    @Environment(\.dismiss) private var dismiss

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
                        ThemeSegmentedControl(
                            options: HistoryRange.allCases.map { ($0, $0.label) },
                            selection: $range)

                        summaryCard
                        chartCard
                        explanationCard
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle(macro.title)
            .themedChrome()
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
                .withoutGlassBackground()
            }
        }
    }

    // MARK: - Data

    /// Per day from food and supplements, so a shake counts either way.
    private var dailyIntake: [Date: Double] {
        let cal = Calendar.current
        var out: [Date: Double] = [:]
        for log in logs where log.date >= start {
            out[cal.startOfDay(for: log.date), default: 0] += macro.grams(log)
        }
        for day in out.keys {
            let supplement = SupplementIntake.total(on: day, entries: supplementEntries,
                                                    supplements: supplements)
            let grams = macro.grams(supplement)
            if grams > 0 { out[day, default: 0] += grams }
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
        for day in dailyIntake.keys {
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
            let targets = calculator.targets(
                kcal: kcal, goal: profile.goal, bodyweightKg: weight.basisWeightKg,
                leanMassKg: weight.leanMassKg, proteinPerKg: override)
            out[cal.startOfDay(for: day)] = macro.target(targets)
        }
        return out
    }

    private var points: [HistorySeries.AdherencePoint] {
        HistorySeries.proteinAdherence(dailyProtein: dailyIntake, dailyTarget: dailyTarget)
    }

    private var hitRate: Double? {
        let all = points
        guard !all.isEmpty else { return nil }
        return Double(all.filter { $0.hit(macro.rule) }.count) / Double(all.count)
    }

    // MARK: - Cards

    private var summaryCard: some View {
        let all = points
        let average = all.isEmpty ? nil
            : all.reduce(0) { $0 + $1.actual } / Double(all.count)
        let target = all.last?.target

        return HStack(spacing: 0) {
            stat("Days on target", hitRate.map { "\(Int(($0 * 100).rounded()))%" } ?? "—")
            Rectangle().fill(Theme.divider).frame(width: 1, height: 44)
            stat("Daily average", average.map { "\(Int($0.rounded())) g" } ?? "—")
            Rectangle().fill(Theme.divider).frame(width: 1, height: 44)
            stat("Target now", target.map { "\(Int($0.rounded())) g" } ?? "—")
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardRadiusCompact, style: .continuous)
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
        let rule = macro.rule
        return HistoryChartCard(
            title: "\(macro.title) vs target",
            height: 190,
            yLabel: { "\(Int($0))g" },
            content: {
                // Bars coloured by whether the day landed, so the pattern of
                // misses is readable without reading any numbers.
                ForEach(all) { point in
                    BarMark(x: .value("Date", point.date, unit: .day),
                            y: .value(macro.title, point.actual))
                        .foregroundStyle(point.hit(rule)
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
            emptyMessage: "Log a few days of food to see how your \(macro.title.lowercased()) tracks against target."
        )
    }

    private var explanationCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Why \(macro.title.lowercased())")
                .font(Theme.font(15))
                .foregroundStyle(Theme.textSecondary)
            Text(explanation)
                .font(Theme.font(14))
                .foregroundStyle(Theme.textPrimary)
            Text(macro.toleranceNote)
                .font(Theme.font(13))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardRadiusCompact, style: .continuous)
                .stroke(Theme.hairline, lineWidth: 1)
        )
    }

    private var explanation: String {
        let usingLean = BodyComposition.recentLeanMassKg(metrics) != nil
        let basis = usingLean ? "lean mass" : "bodyweight"
        switch macro {
        case .protein:
            switch profiles.first?.goal {
            case .fatLoss, .recomposition:
                return "In a deficit, protein is what decides whether the weight you lose is fat or muscle. Your target is set from your \(basis) and moves with it."
            case .muscleGain:
                return "Protein supplies the material for new muscle; the surplus supplies the energy. Your target is set from your \(basis)."
            default:
                return "Protein maintains lean mass at any calorie level. Your target is set from your \(basis)."
            }
        case .carbs:
            return "Carbohydrate is what fuels hard training — it's the fuel your body reaches for first at high intensity. The target is whatever calories are left once protein and fat are set, so it moves with your calorie target rather than with your \(basis)."
        case .fats:
            return "Fat has a floor rather than a goal: it carries the fat-soluble vitamins and supports hormone production, so the target is a minimum worth clearing, not a ceiling to chase. The rest of your calories go to carbohydrate."
        }
    }
}

/// Kept so the nutrition screen's existing entry point still reads as what it is.
struct ProteinAdherenceView: View {
    var body: some View { MacroAdherenceView(macro: .protein) }
}
