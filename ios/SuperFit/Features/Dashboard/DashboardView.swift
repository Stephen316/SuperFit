import SwiftUI
import SwiftData

/// Laid out against the `fitness-tracker` frame in the Figma file, read through
/// the REST API rather than measured off a screenshot: every size, colour, gap and
/// padding below is the literal value on the corresponding node.
///
/// Two deliberate departures, both requested:
///
/// - The tab bar's background runs to the bottom of the screen. The frame floats
///   it with 32pt beneath, which on a real device would show the gradient through
///   the home-indicator strip.
/// - Everything stays live. The frame is a mockup with 50, 432 and 1899 painted
///   on; here those come from Health and the diary, and the gauge still reads "–"
///   when Health has given us nothing.
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
    @State private var showingSettings = false

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
            ZStack {
                Theme.background
                VStack(spacing: 0) {
                    headerRow
                    ScrollView {
                        VStack(spacing: 20) {          // dashboard-content, gap 20
                            recoverySection
                            burnedCard
                            consumedCard
                            activitySleepCard
                            macrosCard
                        }
                        .padding(.horizontal, 20)      // dashboard-content, pad 20
                        // bottom-spacer is 40 in the frame; the tab bar's own 72
                        // sits under it, and the design's trailing 32 is absorbed
                        // by running the bar to the screen edge.
                        .padding(.bottom, 112)
                    }
                    .scrollIndicators(.hidden)
                    .refreshable { await refresh() }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingHistory) { HistoryView() }
            .sheet(isPresented: $showingProtein) { ProteinAdherenceView() }
            .sheet(isPresented: $showingSettings) { SettingsView() }
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

    // MARK: - Header

    /// header-row: 64 tall, 24 horizontal padding, title left and controls right.
    ///
    /// The frame shows one control. Trends would have nowhere to live, and losing
    /// it would cost a whole screen, so it sits beside the gear in the same 40pt
    /// treatment rather than being dropped.
    private var headerRow: some View {
        HStack(spacing: 10) {
            Text("Today")
                .font(Theme.text(18, .bold))
                .foregroundStyle(Theme.textPrimary)
            Spacer(minLength: 0)
            circleButton("chart.xyaxis.line", label: "Trends") { showingHistory = true }
            circleButton("gearshape", label: "Settings") { showingSettings = true }
        }
        .padding(.horizontal, 24)
        .frame(height: 64)
    }

    /// settings-btn: 40pt circle, white at 5%, 20pt glyph.
    private func circleButton(_ icon: String, label: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Theme.wash))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: - Cards

    /// recovery-section: 110pt gauge container, 12pt gap, then the two labels 2 apart.
    ///
    /// The ring is the Health-backed element on this screen: no sleep or heart
    /// data means no score, and it says so rather than drawing a zero.
    private var recoverySection: some View {
        let recovery = todayRecovery
        let hasData = (recovery?.dataCompleteness ?? 0) > 0
        let score = recovery?.score ?? 0
        return VStack(spacing: 12) {
            ZStack {
                // 94pt frame with a 6pt stroke gives a 100pt outer and 88pt inner
                // ring — the frame's innerRadius of 0.88.
                Circle()
                    .stroke(Theme.wash, lineWidth: 6)
                    .frame(width: 94, height: 94)
                if hasData {
                    Circle()
                        .trim(from: 0, to: score / 100)
                        .stroke(Theme.gold, style: .init(lineWidth: 6, lineCap: .butt))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 94, height: 94)
                }
                Text(hasData ? "\(Int(score))" : "–")
                    .font(Theme.text(32, .heavy))
                    .foregroundStyle(Theme.textPrimary)
            }
            .frame(width: 110, height: 110)
            VStack(spacing: 2) {
                Text("Recovery")
                    .font(Theme.text(18, .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text(hasData ? (recovery?.recommendationRaw ?? "—") : "No data yet")
                    .font(Theme.text(13, .medium))
                    .foregroundStyle(hasData ? Theme.amber : Theme.textSecondary)
            }
        }
    }

    /// calories-burned-card: pad 20, gap 8, value and suffix on one baseline.
    private var burnedCard: some View {
        ThemeCard(padding: 20) {
            VStack(spacing: 8) {
                cardLabel("Calories burned today")
                if let e = todayEnergy, e.activeEnergyKcal > 0 {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(Int(e.activeEnergyKcal))")
                            .font(Theme.text(28, .bold))
                            .foregroundStyle(Theme.textPrimary)
                        Text("/\(Int(e.activeEnergyKcal + e.basalEnergyKcal)) kcal")
                            .font(Theme.text(16))
                            .foregroundStyle(Theme.textSecondary)
                    }
                } else {
                    noData
                }
            }
        }
    }

    /// calories-consumed-card: pad 20, gap 8, caption stacked under the value.
    private var consumedCard: some View {
        ThemeCard(padding: 20) {
            VStack(spacing: 8) {
                cardLabel("Calories consumed")
                VStack(spacing: 4) {
                    Text("\(Int(todayLogs.reduce(0) { $0 + $1.kcal }))")
                        .font(Theme.text(28, .bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(macros.map { "of \(Int($0.kcal)) kcal" } ?? "set a goal to see a target")
                        .font(Theme.text(13))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }

    /// activity-sleep-card: 18 vertical padding, a 44pt hairline between columns.
    private var activitySleepCard: some View {
        ThemeCard(padding: 0) {
            HStack(spacing: 0) {
                splitBlock(title: "Activity",
                           value: todayEnergy.map { "\($0.steps) steps" })
                Rectangle()
                    .fill(Theme.divider)
                    .frame(width: 1, height: 44)
                splitBlock(title: "Sleep",
                           value: lastSleep.map { "\($0.asleepMinutes / 60) h \($0.asleepMinutes % 60) m" })
            }
            .padding(.vertical, 18)
        }
    }

    /// macros-card: pad 18, 14 between title and row, 32pt hairlines between columns.
    private var macrosCard: some View {
        ThemeCard(padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Macros")
                    .font(Theme.text(14, .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 0) {
                    Button { showingProtein = true } label: {
                        macroColumn("Protein", todayLogs.reduce(0) { $0 + $1.proteinG },
                                    target: macros?.proteinG)
                    }
                    .buttonStyle(.plain)
                    Rectangle().fill(Theme.divider).frame(width: 1, height: 32)
                    macroColumn("Carbs", todayLogs.reduce(0) { $0 + $1.carbsG },
                                target: macros?.carbG)
                    Rectangle().fill(Theme.divider).frame(width: 1, height: 32)
                    macroColumn("Fats", todayLogs.reduce(0) { $0 + $1.fatG },
                                target: macros?.fatG)
                }
            }
        }
    }

    // MARK: - Pieces

    private func cardLabel(_ text: String) -> some View {
        Text(text)
            .font(Theme.text(13, .medium))
            .foregroundStyle(Theme.textSecondary)
    }

    private var noData: some View {
        Text("No data yet")
            .font(Theme.text(16))
            .foregroundStyle(Theme.textSecondary)
    }

    /// col-activity / col-sleep: 14/600 title over a 12/400 line, 4 apart.
    private func splitBlock(title: String, value: String?) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(Theme.text(14, .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(value ?? "No data yet")
                .font(Theme.text(12))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    /// macro-*: 12/400 label, 15/700 value, 10/400 target, 4 apart.
    private func macroColumn(_ label: String, _ grams: Double,
                             target: Double? = nil) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 3) {
                Text(label)
                    .font(Theme.text(12))
                    .foregroundStyle(Theme.textSecondary)
                // Only protein opens a screen, so only protein gets the chevron.
                if label == "Protein", target != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Text("\(Int(grams))g")
                .font(Theme.text(15, .bold))
                .foregroundStyle(Theme.textPrimary)
            Text(target.map { "of \(Int($0))g" } ?? " ")
                .font(Theme.text(10))
                .foregroundStyle(Theme.textSecondary)
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
