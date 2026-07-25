import SwiftUI
import SwiftData

/// Full nutrient picture for a day: macros and micros against goal-derived
/// targets. The Diary tab stays the logging surface; this is the analysis.
struct NutritionView: View {
    @Query private var profiles: [UserProfile]
    @Query private var logs: [NutritionLog]
    @Query(sort: \BodyMetrics.date, order: .reverse) private var metrics: [BodyMetrics]
    @Query(sort: \MetabolicEstimateRecord.date, order: .reverse) private var estimates: [MetabolicEstimateRecord]
    @Query(sort: \TrainingSession.startedAt, order: .reverse) private var sessions: [TrainingSession]

    @State private var day = Calendar.current.startOfDay(for: .now)
    @State private var averaging = false

    private var profile: UserProfile? { profiles.first }

    private var dayLogs: [NutritionLog] {
        logs.filter { Calendar.current.isDate($0.date, inSameDayAs: day) }
    }

    /// Averaging window smooths the day-to-day swings micronutrients naturally
    /// have — one liver dinner covers a week of vitamin A.
    private var windowLogs: [NutritionLog] {
        guard averaging else { return dayLogs }
        let start = Calendar.current.date(byAdding: .day, value: -6, to: day) ?? day
        return logs.filter { $0.date >= start && $0.date <= day }
    }

    private var divisor: Double {
        guard averaging else { return 1 }
        let days = Set(windowLogs.map { Calendar.current.startOfDay(for: $0.date) }).count
        return Double(max(1, days))
    }

    private var macroTargets: MacroTargets? {
        guard let profile, let w = metrics.first?.weightKg,
              let est = estimates.first(where: { $0.windowDays == 30 }) else { return nil }
        let tdee = TDEEEstimate(tdeeKcal: est.tdeeKcal, confidence: est.confidence,
                                trendSlopeKgPerWeek: est.trendSlopeKgPerWeek,
                                avgIntakeKcal: est.avgIntakeKcal,
                                smoothedWeightKg: w, windowDays: est.windowDays)
        let kcal = MetabolismEngine().calorieTarget(tdee: tdee, goal: profile.goal, bodyweightKg: w)
        let override = profile.proteinPerKgOverride > 0 ? profile.proteinPerKgOverride : nil
        return MacroCalculator().targets(kcal: kcal, goal: profile.goal, bodyweightKg: w,
                                         leanMassKg: metrics.first?.leanMassKg,
                                         proteinPerKg: override)
    }

    private var sessionsPerWeek: Int {
        let start = Calendar.current.date(byAdding: .day, value: -28, to: .now) ?? .now
        let recent = sessions.filter { $0.startedAt >= start && $0.endedAt != nil }
        return Int((Double(recent.count) / 4).rounded())
    }

    private var microTargets: [NutrientTarget] {
        guard let profile, let macros = macroTargets else { return [] }
        let age = Calendar.current.dateComponents([.year], from: profile.birthDate, to: .now).year ?? 30
        return NutrientTargets().targets(.init(sex: profile.sex, ageYears: age,
                                               kcalTarget: macros.kcal, goal: profile.goal,
                                               sessionsPerWeek: sessionsPerWeek))
    }

    private var macroTotals: (kcal: Double, protein: Double, carbs: Double, fat: Double, fibre: Double) {
        let l = windowLogs
        return (l.reduce(0) { $0 + $1.kcal } / divisor,
                l.reduce(0) { $0 + $1.proteinG } / divisor,
                l.reduce(0) { $0 + $1.carbsG } / divisor,
                l.reduce(0) { $0 + $1.fatG } / divisor,
                l.reduce(0) { $0 + $1.fibreG } / divisor)
    }

    private var microTotals: [Micronutrient: Double] {
        var out: [Micronutrient: Double] = [:]
        for log in windowLogs {
            for (nutrient, amount) in log.micros { out[nutrient, default: 0] += amount }
        }
        return out.mapValues { $0 / divisor }
    }

    /// Share of logged energy that came with micronutrient data. Low coverage
    /// means the micro totals understate reality, so the UI must say so.
    private var microCoverage: Double {
        let l = windowLogs
        let total = l.reduce(0) { $0 + $1.kcal }
        guard total > 0 else { return 0 }
        let covered = l.filter { !$0.microsRaw.isEmpty }.reduce(0) { $0 + $1.kcal }
        return covered / total
    }

    var body: some View {
        NavigationStack {
            List {
                if windowLogs.isEmpty {
                    emptySection
                } else {
                    macroSection
                    if microTargets.isEmpty {
                        needsProfileSection
                    } else {
                        ForEach(Micronutrient.Group.allCases, id: \.self) { group in
                            microSection(group)
                        }
                        coverageFooter
                    }
                }
            }
            .navigationTitle(averaging ? "Nutrition — 7-day average" : "Nutrition")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                        .accessibilityLabel("Previous day")
                        .disabled(averaging)
                    Button { shift(1) } label: { Image(systemName: "chevron.right") }
                        .disabled(averaging || Calendar.current.isDateInToday(day))
                        .accessibilityLabel("Next day")
                    Button { averaging.toggle() } label: {
                        Image(systemName: averaging ? "calendar.badge.clock" : "calendar")
                    }
                    .accessibilityLabel(averaging ? "Show single day" : "Show 7-day average")
                }
            }
            .settingsToolbar()
        }
    }

    // MARK: - Sections

    private var macroSection: some View {
        Section {
            if let t = macroTargets {
                let m = macroTotals
                NutrientBar(label: "Calories", value: m.kcal, target: t.kcal, unit: "kcal")
                NutrientBar(label: "Protein", value: m.protein, target: t.proteinG, unit: "g")
                NutrientBar(label: "Carbs", value: m.carbs, target: t.carbG, unit: "g")
                NutrientBar(label: "Fat", value: m.fat, target: t.fatG, unit: "g")
                NutrientBar(label: "Fibre", value: m.fibre, target: t.fibreG, unit: "g")
            } else {
                Text("Log your weight and set a goal to get targets.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        } header: {
            Text(averaging ? "Macros — daily average" : "Macros")
        } footer: {
            if let profile, macroTargets != nil {
                Text(goalExplanation(profile.goal))
            }
        }
    }

    private func microSection(_ group: Micronutrient.Group) -> some View {
        let targets = microTargets.filter { $0.nutrient.group == group }
        let totals = microTotals
        return Section(group.displayName) {
            ForEach(targets, id: \.nutrient) { target in
                NutrientBar(label: target.nutrient.displayName,
                            value: totals[target.nutrient] ?? 0,
                            target: target.amount,
                            unit: target.nutrient.unit,
                            isLimit: target.isLimit,
                            note: target.reason)
            }
        }
    }

    private var coverageFooter: some View {
        Section {
            EmptyView()
        } footer: {
            if microCoverage < 0.9 {
                Text("\(Int(microCoverage * 100))% of today's calories came from foods with full nutrient data. Custom foods and some branded items only carry macros, so micronutrient totals read low.")
            } else {
                Text("Targets are reference intakes adjusted for your sex, age, and training volume. Micronutrients swing day to day — the 7-day average is the more honest read.")
            }
        }
    }

    private var needsProfileSection: some View {
        Section {
            Text("Add your details in Settings → Profile to see micronutrient targets.")
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private var emptySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("Nothing logged \(averaging ? "this week" : "yet")").font(.headline)
                Text("Food you log in the Diary tab appears here, broken down into macros and micronutrients against your targets.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
        }
    }

    private func goalExplanation(_ goal: FitnessGoal) -> String {
        switch goal {
        case .muscleGain:
            return "Protein is set high to support muscle gain, with a calorie surplus above your measured expenditure."
        case .fatLoss:
            return "Protein stays high to protect lean mass in a deficit; calories sit below your measured expenditure."
        case .recomposition:
            return "Protein is set at the upper end to build muscle while calories run slightly below expenditure."
        case .maintenance:
            return "Calories match your measured expenditure, with protein set to maintain lean mass."
        }
    }

    private func shift(_ days: Int) {
        day = Calendar.current.date(byAdding: .day, value: days, to: day) ?? day
    }
}

/// One nutrient row: amount vs target with a progress bar. Floors fill toward
/// the target; limits warn as they approach and turn red past it.
struct NutrientBar: View {
    let label: String
    let value: Double
    let target: Double
    let unit: String
    var isLimit = false
    var note: String?

    private var fraction: Double { target <= 0 ? 0 : min(value / target, 1) }
    private var over: Bool { target > 0 && value > target }

    private var tint: Color {
        if isLimit { return over ? .red : (fraction > 0.85 ? .orange : .secondary) }
        if over { return .green }
        return fraction >= 0.7 ? .accentColor : .orange
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(label).font(.subheadline)
                Spacer()
                Text("\(format(value)) / \(format(target)) \(unit)")
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.tertiarySystemFill))
                    Capsule().fill(tint).frame(width: geo.size.width * fraction)
                }
            }
            .frame(height: 4)
            if let note {
                Text(note).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(format(value)) of \(format(target)) \(unit)")
    }

    private func format(_ v: Double) -> String {
        v >= 100 ? "\(Int(v.rounded()))" : String(format: v >= 10 ? "%.0f" : "%.1f", v)
    }
}
