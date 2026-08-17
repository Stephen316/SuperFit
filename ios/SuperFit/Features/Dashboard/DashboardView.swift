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
    /// Owned by `RootView`. Cards that lead to a whole section switch tab rather
    /// than pushing a second copy of a screen that already exists.
    @Binding var tab: AppTab

    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]
    @Query private var supplements: [Supplement]
    @Query private var supplementEntries: [SupplementEntry]

    // Explicit, windowed fetches rather than reactive whole-table queries. The
    // dashboard needs one selected day plus a year for its streak; retaining every
    // historical model made the first screen grow with the lifetime of the app.
    @State private var metrics: [BodyMetrics] = []
    @State private var nutrition: [NutritionLog] = []
    @State private var estimates: [MetabolicEstimateRecord] = []
    @State private var recoveries: [RecoveryScoreRecord] = []
    @State private var strains: [StrainRecord] = []
    @State private var energy: [DailyEnergy] = []
    @State private var sleep: [SleepData] = []
    @State private var vitals: [DailyVitals] = []
    @State private var workouts: [WorkoutRecord] = []

    /// The day on screen. Every card reads from this rather than "now", so the
    /// arrows under the title move the whole page together.
    @State private var day = Calendar.current.startOfDay(for: .now)
    @State private var addingTo: MealSlot?
    @State private var syncing = false
    @State private var showingMacro: TrackedMacro?
    @State private var showingConsumed = false
    @State private var showingSteps = false
    @State private var showingRestingHR = false
    @State private var showingSettings = false
    @State private var showingWatchHelp = false
    @State private var syncFailure: String?
    @AppStorage(UnitSystem.storageKey) private var unitsRaw = UnitSystem.metric.rawValue

    private var units: UnitSystem { UnitSystem(rawValue: unitsRaw) ?? .metric }

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
                                         leanMassKg: BodyComposition.recentLeanMassKg(metrics),
                                         proteinPerKg: override)
    }

    /// Built once per filter, then compared against. See `DayBounds` — asking
    /// the calendar per row is 43x the cost and every card here filters.
    private var bounds: DayBounds { DayBounds(day) }

    private var isToday: Bool { Calendar.current.isDateInToday(day) }

    private var todayLogs: [NutritionLog] {
        let d = bounds
        return nutrition.filter { d.contains($0.date) }
    }

    /// Food plus supplements, which is what the day actually was.
    ///
    /// This card used to sum `todayLogs` alone while the diary, the macro pages,
    /// the trends and the metabolism engine all folded supplements in. Three
    /// shakes is ~340 kcal, so the home screen and the Diet tab quietly disagreed
    /// about the same day — and the home screen was the one that was wrong.
    private var dayTotals: NutrientProfile {
        var t = todayLogs.reduce(into: NutrientProfile()) {
            $0.kcal += $1.kcal; $0.proteinG += $1.proteinG
            $0.carbsG += $1.carbsG; $0.fatG += $1.fatG; $0.fibreG += $1.fibreG
        }
        let s = SupplementIntake.total(on: day, entries: supplementEntries,
                                       supplements: supplements)
        t.kcal += s.kcal; t.proteinG += s.proteinG
        t.carbsG += s.carbsG; t.fatG += s.fatG; t.fibreG += s.fibreG
        return t
    }
    private var todayRecovery: RecoveryScoreRecord? {
        let d = bounds
        return recoveries.first { d.contains($0.date) }
    }
    private var todayStrain: StrainRecord? {
        let d = bounds
        return strains.first { d.contains($0.date) }
    }

    /// Live energy level from everything already loaded plus the clock. Computed
    /// in the view rather than stored: a battery drains through the day, so a
    /// value frozen at the last sync would be stale by the afternoon.
    private var energyLevel: EnergyEngine.Result? {
        let frac: Double = {
            guard isToday else { return 1 } // a past day is "spent"
            let cal = Calendar.current
            let wake = lastSleep?.wakeTime
                ?? cal.date(bySettingHour: 7, minute: 0, second: 0, of: .now)
                ?? .now
            return min(max(Date.now.timeIntervalSince(wake) / (16 * 3600), 0), 1)
        }()
        let recovery = (todayRecovery?.dataCompleteness ?? 0) > 0 ? todayRecovery?.score : nil
        let strain = (todayStrain?.dataCompleteness ?? 0) > 0 ? todayStrain?.strain : nil
        let inputs = EnergyEngine.Inputs(
            recoveryScore: recovery,
            strain: strain,
            activeEnergyKcal: todayEnergy.map(\.activeEnergyKcal),
            steps: todayEnergy.map(\.steps),
            intakeKcal: dayTotals.kcal > 0 ? dayTotals.kcal : nil,
            targetKcal: macros?.kcal,
            dayFraction: frac)
        return EnergyEngine().evaluate(inputs)
    }
    private var todayEnergy: DailyEnergy? {
        let d = bounds
        return energy.first { d.contains($0.date) }
    }
    private var lastSleep: SleepData? {
        let d = bounds
        return sleep.first { d.contains($0.date) }
    }
    private var latestSleepScore: OverallSleepScore? {
        guard let row = lastSleep else { return nil }
        let night = SleepNight(date: row.date,
                               asleepMinutes: row.asleepMinutes,
                               inBedMinutes: row.inBedMinutes,
                               deepMinutes: row.deepMinutes,
                               remMinutes: row.remMinutes,
                               coreMinutes: row.coreMinutes,
                               bedtime: row.bedtime,
                               wakeTime: row.wakeTime)
        return SleepAnalytics().overallScore(for: night)
    }
    private var todayVitals: DailyVitals? {
        let d = bounds
        return vitals.first { d.contains($0.date) }
    }
    private var todayWorkouts: [WorkoutRecord] {
        let d = bounds
        return workouts.filter { d.contains($0.startedAt) }
    }

    /// Whether any watch-sourced reading has ever reached the store. This gates
    /// the setup help: an empty card on a connected watch usually just means the
    /// value hasn't synced yet — resting HR lags to the afternoon — so a set-up
    /// user shouldn't be told to reconnect on an ordinary data gap. Only a store
    /// with no heart or sleep data at all is treated as "no watch".
    private var watchConnected: Bool {
        vitals.contains { $0.restingHR != nil || $0.hrvSDNN != nil }
            || sleep.contains { $0.asleepMinutes > 0 }
    }

    /// The weight to show is the one recorded on the day being viewed, falling
    /// back to the most recent before it — stepping back a day shouldn't blank
    /// the card just because nothing was weighed that morning.
    ///
    /// Several readings on the viewed day resolve to the lowest, matching what
    /// the engines count. Taking the most recent row instead meant an evening
    /// re-weigh showed a heavier number here than the one the calorie target was
    /// built from.
    private var weightOnDay: BodyMetrics? {
        let d = bounds
        let sameDay = metrics.filter { d.contains($0.date) }
        if !sameDay.isEmpty { return sameDay.min { $0.weightKg < $1.weightKg } }
        return metrics.first { $0.date < d.end }
    }

    /// The meal slot closest to the time of day, so the card offers the one you
    /// are most likely about to eat. On a past day there is no "about to", so it
    /// falls back to the last slot of the day.
    private var nextMeal: MealSlot {
        guard isToday else { return .dinner }
        switch Calendar.current.component(.hour, from: .now) {
        case ..<11: return .breakfast
        case ..<16: return .lunch
        case ..<21: return .dinner
        default: return .snack
        }
    }

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
                            energyCard
                            macrosCard
                            stepsCard
                            nextMealCard
                            weightCard
                            restingHRCard
                            activitySleepCard
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
            .sheet(item: $showingMacro) { MacroAdherenceView(macro: $0) }
            .sheet(isPresented: $showingConsumed) { ConsumedFoodsView(day: day) }
            .sheet(isPresented: $showingSteps) { StepsHistoryView() }
            .sheet(isPresented: $showingRestingHR) { RestingHRHistoryView() }
            .sheet(isPresented: $showingSettings) { SettingsView() }
            .sheet(isPresented: $showingWatchHelp) { WatchSetupHelpView() }
            .sheet(item: $addingTo, onDismiss: loadDashboardData) { slot in
                FoodSearchView(day: day, meal: slot)
            }
            .alert("Refresh incomplete", isPresented: Binding(
                get: { syncFailure != nil },
                set: { if !$0 { syncFailure = nil } })) {
                Button("OK", role: .cancel) { syncFailure = nil }
            } message: {
                Text(syncFailure ?? "")
            }
            .task {
                // Repair legacy derived values before the first read, without
                // waiting for Health authorization or a network-backed source.
                AggregationService(context: context).repairWeightTrendIfNeeded()
                loadDashboardData()
                await refresh()
            }
            .onChange(of: day) { _, _ in loadDashboardData() }
            .onChange(of: tab) { _, selected in
                if selected == .home { loadDashboardData() }
            }
        }
    }

    private func refresh() async {
        guard !syncing else { return }
        syncing = true
        defer { syncing = false }
        let aggregation = AggregationService(context: context)
        let changes = await SyncCoordinator(context: context).syncAll()
        syncFailure = changes.failureMessage
        aggregation.runAll(refreshWeightTrend: changes.weightTrendNeedsRefresh)
        loadDashboardData()
    }

    /// Loads exactly what the cards can consume while preserving unlimited day
    /// navigation: an old selected day is OR'd into the one-year streak window,
    /// and the last weight before that day is fetched separately for carry-forward.
    private func loadDashboardData() {
        do {
            let loaded = try DashboardDataLoader.load(context: context, day: day)
            metrics = loaded.metrics
            nutrition = loaded.nutrition
            estimates = loaded.estimates
            recoveries = loaded.recoveries
            strains = loaded.strains
            energy = loaded.energy
            sleep = loaded.sleep
            vitals = loaded.vitals
            workouts = loaded.workouts
        } catch {
            syncFailure = "Loading dashboard: \(error.localizedDescription)"
        }
    }

    // MARK: - Header

    /// header-row: 64 tall, 24 horizontal padding, title left and controls right.
    ///
    /// The streak sits where Trends used to. Trends moved into Settings rather
    /// than being deleted — that button was the only route to it.
    private var headerRow: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text(DayTitle.text(for: day))
                    .font(Theme.text(18, .bold))
                    .foregroundStyle(Theme.textPrimary)
                DayStepper(day: $day)
            }
            Spacer(minLength: 0)
            streakBadge
            circleButton("gearshape", label: "Settings") { showingSettings = true }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }

    /// Consecutive days of food logged, with a weigh-in every third day.
    ///
    /// The rule lives in `LoggingStreak` so it can be tested without a store.
    private var loggingStreak: Int {
        let cal = Calendar.current
        let earliest = cal.date(byAdding: .day, value: -LoggingStreak.maximumDays,
                                to: cal.startOfDay(for: .now)) ?? .distantPast
        return LoggingStreak.days(
            foodDays: Set(nutrition.filter { $0.date >= earliest }.map(\.date)),
            // `weightKg` is defaulted, not optional, so a body-fat-only row
            // reads as 0. That is not a weigh-in and must not hold a streak up.
            weighDays: Set(metrics.filter { $0.date >= earliest && $0.weightKg > 0 }
                .map(\.date)),
            asOf: .now, calendar: cal)
    }

    /// The streak, lit from two consecutive days.
    ///
    /// Two, not one. A single logged day is not a streak, and a flame that lit
    /// on day one would be lit almost permanently — which would make it mean
    /// nothing. The unlit state still shows the count, so day one reads as
    /// progress towards something rather than as a failure.
    private var streakBadge: some View {
        let streak = loggingStreak
        let lit = streak >= 2
        return HStack(spacing: 5) {
            Image(systemName: lit ? "flame.fill" : "flame")
                .font(.system(size: 16))
                .foregroundStyle(lit ? Theme.gold : Theme.textSecondary.opacity(0.55))
            Text("\(streak)")
                .font(Theme.text(15, .semibold))
                .monospacedDigit()
                .foregroundStyle(lit ? Theme.textPrimary : Theme.textSecondary)
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(Capsule().fill(Theme.wash))
        .overlay(Capsule().strokeBorder(lit ? Theme.gold.opacity(0.45) : Theme.hairline,
                                        lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(lit
                            ? "Logging streak, \(streak) days"
                            : "No logging streak yet, \(streak) of 2 days")
    }

    /// settings-btn: 40pt visible circle inside a 44pt touch target.
    private func circleButton(_ icon: String, label: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle().fill(Theme.wash).frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.textPrimary)
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: - Cards

    /// recovery-section: three gauges across — Recovery (how ready), Strain (how
    /// hard today was) and Sleep (overall quality), the triad Bevel and WHOOP show.
    ///
    /// All are Health-backed: no sleep or heart data means no recovery score, no
    /// heart-rate-carrying workout means no strain, and no sleep duration means no
    /// sleep score — each says so rather than drawing a zero. The setup-help link
    /// appears only when none has data and no watch is connected, so a set-up user
    /// on a plain rest day isn't nagged.
    private var recoverySection: some View {
        let recovery = todayRecovery
        let recoveryHasData = (recovery?.dataCompleteness ?? 0) > 0
        let strain = todayStrain
        let strainHasData = (strain?.dataCompleteness ?? 0) > 0
        let sleepScore = latestSleepScore
        let sleepHasData = sleepScore != nil
        let needsWatch = !recoveryHasData && !strainHasData && !sleepHasData && !watchConnected
        return VStack(spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                metricGauge(
                    title: "Recovery",
                    value: recovery?.score ?? 0,
                    hasData: recoveryHasData,
                    subtitle: recoveryHasData ? (recovery?.recommendationRaw ?? "—") : "No data yet",
                    tint: Theme.gold)
                metricGauge(
                    title: "Strain",
                    value: strain?.strain ?? 0,
                    hasData: strainHasData,
                    subtitle: strainHasData ? strainSubtitle(strain) : "No data yet",
                    tint: Theme.strain)
                metricGauge(
                    title: "Sleep",
                    value: sleepScore?.score ?? 0,
                    hasData: sleepHasData,
                    subtitle: sleepHasData
                        ? (sleepScore?.band.rawValue ?? "—")
                        : "No data yet",
                    tint: Theme.sleep)
            }
            if needsWatch {
                Button { showingWatchHelp = true } label: { WatchHelpLabel() }
                    .buttonStyle(.plain)
            }
        }
    }

    private func strainSubtitle(_ strain: StrainRecord?) -> String {
        let band = strain?.bandRaw ?? ""
        return band.isEmpty ? "—" : band
    }

    /// One ring gauge — a 0…100 value over a wash track, a title and a subtitle.
    /// Shared by the paired Recovery and Strain gauges so they read as one unit.
    private func metricGauge(title: String, value: Double, hasData: Bool,
                             subtitle: String, tint: Color) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(Theme.wash, lineWidth: 5)
                    .frame(width: 76, height: 76)
                if hasData {
                    Circle()
                        .trim(from: 0, to: min(max(value / 100, 0), 1))
                        .stroke(tint, style: .init(lineWidth: 5, lineCap: .butt))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 76, height: 76)
                }
                Text(hasData ? "\(Int(value))" : "–")
                    .font(Theme.text(24, .heavy))
                    .foregroundStyle(Theme.textPrimary)
            }
            .frame(width: 84, height: 84)
            VStack(spacing: 2) {
                Text(title)
                    .font(Theme.text(15, .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text(subtitle)
                    .font(Theme.text(11, .medium))
                    .foregroundStyle(hasData ? tint : Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// calories-burned-card: pad 20, gap 8, value and suffix on one baseline.
    private var burnedCard: some View {
        cardButton { tab = .train } content: {
            VStack(spacing: 8) {
                cardLabel("Calories burned")
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
        cardButton { showingConsumed = true } content: {
            VStack(spacing: 8) {
                cardLabel("Calories consumed")
                VStack(spacing: 4) {
                    Text("\(Int(dayTotals.kcal))")
                        .font(Theme.text(28, .bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(macros.map { "of \(Int($0.kcal)) kcal" } ?? "set a goal to see a target")
                        .font(Theme.text(13))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }

    /// energy-card: text on the left, a charge-coloured battery on the right.
    /// The level reads from recovery, exertion, the clock and fuelling — and from
    /// phone steps and the diary alone when there's no watch, so it's rarely blank.
    private var energyCard: some View {
        let energy = energyLevel
        let hasData = energy != nil
        let level = energy?.level ?? 0
        let colour = energyColour(level)
        return ThemeCard(padding: 20) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    cardLabel("Energy")
                    if hasData {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(Int(level))%")
                                .font(Theme.text(28, .bold))
                                .foregroundStyle(Theme.textPrimary)
                            Text(energy?.band.rawValue ?? "")
                                .font(Theme.text(14, .medium))
                                .foregroundStyle(Theme.gold)
                        }
                    } else {
                        Text("No data yet")
                            .font(Theme.text(16))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                Spacer(minLength: 12)
                BatteryView(fraction: level / 100, hasData: hasData, tint: colour)
            }
        }
    }

    /// Red when drained through amber to green when full — a continuous hue ramp,
    /// so the colour tracks the charge rather than snapping between bands.
    private func energyColour(_ level: Double) -> Color {
        let t = min(max(level / 100, 0), 1)
        return Color(hue: 0.33 * t, saturation: 0.72, brightness: 0.88)
    }

    /// activity-sleep-card: 18 vertical padding, a 44pt hairline between columns.
    private var activitySleepCard: some View {
        ThemeCard(padding: 0) {
            HStack(spacing: 0) {
                // Type and minutes, per the sketch — steps moved to their own card.
                splitBlock(title: "Activity", value: activitySummary)
                Rectangle()
                    .fill(Theme.divider)
                    .frame(width: 1, height: 44)
                splitBlock(title: "Sleep", value: sleepSummary)
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
                let totals = dayTotals
                HStack(spacing: 0) {
                    macroButton(.protein, totals.proteinG, target: macros?.proteinG)
                    Rectangle().fill(Theme.divider).frame(width: 1, height: 32)
                    macroButton(.carbs, totals.carbsG, target: macros?.carbG)
                    Rectangle().fill(Theme.divider).frame(width: 1, height: 32)
                    macroButton(.fats, totals.fatG, target: macros?.fatG)
                }
            }
        }
    }

    /// Steps stand alone rather than sharing the Activity column, which now
    /// carries the day's workout instead.
    private var stepsCard: some View {
        cardButton { showingSteps = true } content: {
            VStack(spacing: 8) {
                cardLabel("Steps")
                Text(todayEnergy.map { "\($0.steps)" } ?? "–")
                    .font(Theme.text(28, .bold))
                    .foregroundStyle(Theme.textPrimary)
            }
        }
    }

    /// The meal you're most likely about to eat, with whatever is already in it.
    /// Tapping opens the same search the diary uses, logging into that slot.
    private var nextMealCard: some View {
        let slot = nextMeal
        let logged = todayLogs.filter { $0.mealRaw == slot.rawValue }
        let kcal = Int(logged.reduce(0) { $0 + $1.kcal })
        return Button { addingTo = slot } label: {
            ThemeCard(padding: 20) {
                VStack(spacing: 8) {
                    cardLabel(isToday ? "Next meal" : "Last meal")
                    Text(slot.rawValue.capitalized)
                        .font(Theme.text(28, .bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(logged.isEmpty
                         ? "Nothing logged — tap to add"
                         : "\(logged.count) item\(logged.count == 1 ? "" : "s") · \(kcal) kcal")
                        .font(Theme.text(13))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var weightCard: some View {
        cardButton { tab = .weight } content: {
            VStack(spacing: 8) {
                cardLabel("Weight")
                Text(weightOnDay.map { units.weightString($0.weightKg) } ?? "–")
                    .font(Theme.text(28, .bold))
                    .foregroundStyle(Theme.textPrimary)
            }
        }
    }

    private var restingHRCard: some View {
        // Any resting HR ever recorded means the history view is worth reaching,
        // even if today's reading hasn't landed. A store that has never seen one
        // sends the tap to the watch setup help instead.
        let hasHistory = vitals.contains { $0.restingHR != nil }
        return cardButton {
            if hasHistory { showingRestingHR = true } else { showingWatchHelp = true }
        } content: {
            VStack(spacing: 8) {
                cardLabel("Resting HR")
                if hasHistory {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(todayVitals?.restingHR.map { "\(Int($0))" } ?? "–")
                            .font(Theme.text(28, .bold))
                            .foregroundStyle(Theme.textPrimary)
                        Text("bpm")
                            .font(Theme.text(16))
                            .foregroundStyle(Theme.textSecondary)
                    }
                } else {
                    WatchHelpLabel(text: "Connect a watch")
                }
            }
        }
    }

    // MARK: - Pieces

    /// "Run · 42 min". Several workouts collapse to a count rather than a list —
    /// the column is one line wide.
    private var activitySummary: String? {
        let all = todayWorkouts
        guard !all.isEmpty else { return nil }
        let minutes = Int(all.reduce(0) { $0 + $1.durationSeconds } / 60)
        let name = all.count == 1
            ? all[0].activity.displayName
            : "\(all.count) sessions"
        return "\(name) · \(minutes) min"
    }

    /// "92% · 7h 20m", dropping the efficiency when Health didn't record it.
    private var sleepSummary: String? {
        guard let s = lastSleep else { return nil }
        let hours = "\(s.asleepMinutes / 60)h \(s.asleepMinutes % 60)m"
        guard let eff = s.efficiency else { return hours }
        return "\(Int(eff * 100))% · \(hours)"
    }

    /// A whole card as one tap target.
    ///
    /// `.plain` throughout: the default button style tints every label inside
    /// blue, which would repaint the numbers these cards exist to show.
    private func cardButton<Content: View>(
        _ action: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Button(action: action) {
            ThemeCard(padding: 20) { content() }
        }
        .buttonStyle(.plain)
    }

    /// One macro column, tappable through to its own page.
    private func macroButton(_ macro: TrackedMacro, _ grams: Double,
                             target: Double?) -> some View {
        Button { showingMacro = macro } label: {
            macroColumn(macro.title, grams, target: target)
        }
        .buttonStyle(.plain)
    }

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
                // All three open a page now, so all three carry the chevron —
                // and unconditionally: the page is worth reaching before a
                // target exists, so the affordance can't depend on having one.
                Image(systemName: "chevron.right")
                    .font(.system(size: 8))
                    .foregroundStyle(Theme.textSecondary)
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
            // Matches the home screen's `circleButton`: a 40pt Theme.wash
            // circle with a size-17 icon in a 44pt hit area, so the gear looks
            // the same in every tab's toolbar as it does on the Dashboard.
            ZStack {
                Circle().fill(Theme.wash).frame(width: 40, height: 40)
                Image(systemName: "gearshape")
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.textPrimary)
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Settings")
        .sheet(isPresented: $showing) { SettingsView() }
    }
}
