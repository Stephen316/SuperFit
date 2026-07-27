import SwiftUI
import SwiftData

struct DashboardView: View {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]
    @Query(sort: \BodyMetrics.date, order: .reverse) private var metrics: [BodyMetrics]
    @Query private var nutrition: [NutritionLog]
    @Query(sort: \MetabolicEstimateRecord.date, order: .reverse) private var estimates: [MetabolicEstimateRecord]
    @Query(sort: \RecoveryScoreRecord.date, order: .reverse) private var recoveries: [RecoveryScoreRecord]
    @Query(sort: \DailyEnergy.date, order: .reverse) private var energy: [DailyEnergy]
    @Query(sort: \SleepData.date, order: .reverse) private var sleep: [SleepData]

    @State private var syncing = false
    @State private var showingHistory = false
    @State private var showingProtein = false

    private var profile: UserProfile? { profiles.first }
    private var latestWeight: Double? { metrics.first?.basisWeightKg }
    private var headline: MetabolicEstimateRecord? { estimates.first { $0.windowDays == 30 } }

    private var macros: MacroTargets? {
        guard let profile, let est = headline, let w = latestWeight else { return nil }
        let tdee = TDEEEstimate(tdeeKcal: est.tdeeKcal, confidence: est.confidence,
                                trendSlopeKgPerWeek: est.trendSlopeKgPerWeek,
                                avgIntakeKcal: est.avgIntakeKcal,
                                smoothedWeightKg: w, windowDays: est.windowDays,
                                basalKcal: est.basalKcal)
        let target = MetabolismEngine().calorieTarget(tdee: tdee, goal: profile.goal, bodyweightKg: w)
        let override = profile.proteinPerKgOverride > 0 ? profile.proteinPerKgOverride : nil
        return MacroCalculator().targets(kcal: target, goal: profile.goal, bodyweightKg: w,
                                         leanMassKg: metrics.first?.leanMassKg,
                                         proteinPerKg: override)
    }

    private var todayLogs: [NutritionLog] {
        nutrition.filter { Calendar.current.isDateInToday($0.date) }
    }

    private var todayRecovery: RecoveryScoreRecord? {
        recoveries.first { Calendar.current.isDateInToday($0.date) }
    }

    private var todayEnergy: DailyEnergy? {
        energy.first { Calendar.current.isDateInToday($0.date) }
    }

    private var lastSleep: SleepData? { sleep.first }

    var body: some View {
        NavigationStack {
            ThemedScreen(title: "") {
                recoveryHeader
                burnedCard
                consumedCard
                activitySleepCard
                macrosCard
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingHistory = true } label: {
                        Image(systemName: "chart.xyaxis.line")
                            .font(.system(size: 19))
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .accessibilityLabel("Trends")
                }
                ToolbarItem(placement: .topBarTrailing) { SettingsGear() }
            }
            .sheet(isPresented: $showingHistory) { HistoryView() }
            .sheet(isPresented: $showingProtein) { ProteinAdherenceView() }
            .refreshable { await refresh() }
            .task { await refresh() }
        }
    }

    private func refresh() async {
        guard !syncing else { return }
        syncing = true
        defer { syncing = false }
        await SyncCoordinator(context: context).syncAll()
        AggregationService(context: context).runAll()
    }

    // MARK: - Cards

    private var recoveryHeader: some View {
        let recovery = todayRecovery
        let hasData = (recovery?.dataCompleteness ?? 0) > 0
        let score = recovery?.score ?? 0
        return VStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(Theme.gold.opacity(hasData ? 0.30 : 0.15), lineWidth: 14)
                    .frame(width: 190, height: 190)
                if hasData {
                    Circle()
                        .trim(from: 0, to: score / 100)
                        .stroke(Theme.gold, style: .init(lineWidth: 14, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 190, height: 190)
                }
                Text(hasData ? "\(Int(score))" : "–")
                    .font(Theme.font(64, .regular))
                    .foregroundStyle(Theme.textPrimary)
            }
            Text("Recovery")
                .font(Theme.font(30))
                .foregroundStyle(Theme.textSecondary)
            Text(hasData ? (recovery?.recommendationRaw ?? "—") : "No data yet")
                .font(Theme.font(20))
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.top, 4)
        .padding(.bottom, 10)
    }

    private var burnedCard: some View {
        ThemeCard {
            if let e = todayEnergy, e.activeEnergyKcal > 0 {
                StatBlock(title: "Calories burned today",
                          value: "\(Int(e.activeEnergyKcal))",
                          suffix: "/\(Int(e.activeEnergyKcal + e.basalEnergyKcal)) kcal")
            } else {
                StatBlock(title: "Calories burned today", value: "No data yet", valueSize: 20)
            }
        }
    }

    private var consumedCard: some View {
        ThemeCard(padding: 22) {
            StatBlock(title: "Calories consumed",
                      value: "\(Int(todayLogs.reduce(0) { $0 + $1.kcal }))",
                      caption: macros.map { "of \(Int($0.kcal)) kcal" } ?? "set a goal to see a target",
                      valueSize: 42)
        }
    }

    private var activitySleepCard: some View {
        ThemeCard(padding: 22) {
            HStack(spacing: 0) {
                splitBlock(title: "Activity",
                           value: todayEnergy.map { "\($0.steps) steps" },
                           caption: todayEnergy.map { "\(Int($0.activeEnergyKcal)) kcal active" })
                Rectangle()
                    .fill(Theme.divider)
                    .frame(width: 1, height: 92)
                splitBlock(title: "Sleep",
                           value: lastSleep.map { "\($0.asleepMinutes / 60) h \($0.asleepMinutes % 60) m" },
                           caption: lastSleep?.efficiency.map { "\(Int($0 * 100))% efficiency" })
            }
        }
    }

    private var macrosCard: some View {
        ThemeCard(padding: 20) {
            VStack(spacing: 12) {
                Text("Macros")
                    .font(Theme.font(15))
                    .foregroundStyle(Theme.textPrimary)
                HStack(spacing: 0) {
                    Button { showingProtein = true } label: {
                        macroColumn("Protein", todayLogs.reduce(0) { $0 + $1.proteinG },
                                    target: macros?.proteinG)
                    }
                    .buttonStyle(.plain)
                    Rectangle().fill(Theme.divider).frame(width: 1, height: 70)
                    macroColumn("Carbs", todayLogs.reduce(0) { $0 + $1.carbsG })
                    Rectangle().fill(Theme.divider).frame(width: 1, height: 70)
                    macroColumn("Fats", todayLogs.reduce(0) { $0 + $1.fatG })
                }
            }
        }
    }

    // MARK: - Pieces

    private func splitBlock(title: String, value: String?, caption: String?) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(Theme.font(20))
                .foregroundStyle(Theme.textPrimary)
            Text(value ?? "No data yet")
                .font(Theme.font(value == nil ? 15 : 18))
                .foregroundStyle(value == nil ? Theme.textSecondary : Theme.textPrimary)
            if let caption {
                Text(caption)
                    .font(Theme.font(13))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func macroColumn(_ label: String, _ grams: Double,
                             target: Double? = nil) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 3) {
                Text(label)
                    .font(Theme.font(16))
                    .foregroundStyle(Theme.textPrimary)
                // Only protein is tappable, so only protein gets the chevron.
                if target != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Text("\(Int(grams)) g")
                .font(Theme.font(30))
                .foregroundStyle(Theme.textPrimary)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Gear used by every screen's trailing toolbar slot.
struct SettingsGear: View {
    @State private var showing = false

    var body: some View {
        Button { showing = true } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 20))
                .foregroundStyle(Theme.textPrimary)
        }
        .accessibilityLabel("Settings")
        .sheet(isPresented: $showing) { SettingsView() }
    }
}
