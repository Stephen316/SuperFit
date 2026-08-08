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
    @Query(sort: \BodyMetrics.date, order: .reverse) private var metrics: [BodyMetrics]
    @Query private var nutrition: [NutritionLog]
    @Query(sort: \MetabolicEstimateRecord.date, order: .reverse) private var estimates: [MetabolicEstimateRecord]
    @Query(sort: \RecoveryScoreRecord.date, order: .reverse) private var recoveries: [RecoveryScoreRecord]
    @Query(sort: \DailyEnergy.date, order: .reverse) private var energy: [DailyEnergy]
    @Query(sort: \SleepData.date, order: .reverse) private var sleep: [SleepData]
    @Query(sort: \DailyVitals.date, order: .reverse) private var vitals: [DailyVitals]
    @Query(sort: \WorkoutRecord.startedAt, order: .reverse) private var workouts: [WorkoutRecord]
    @Query private var supplements: [Supplement]
    @Query private var supplementEntries: [SupplementEntry]

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
    private var todayEnergy: DailyEnergy? {
        let d = bounds
        return energy.first { d.contains($0.date) }
    }
    private var lastSleep: SleepData? {
        let d = bounds
        return sleep.first { d.contains($0.date) }
    }
    private var todayVitals: DailyVitals? {
        let d = bounds
        return vitals.first { d.contains($0.date) }
    }
    private var todayWorkouts: [WorkoutRecord] {
        let d = bounds
        return workouts.filter { d.contains($0.startedAt) }
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
                            activitySleepCard
                            macrosCard
                            stepsCard
                            nextMealCard
                            weightCard
                            restingHRCard
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
            .sheet(item: $addingTo) { slot in FoodSearchView(day: day, meal: slot) }
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
    /// The streak sits where Trends used to. Trends moved into Settings rather
    /// than being deleted — that button was the only route to it.
    private var headerRow: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text(isToday ? "Today" : Self.dayFormatter.string(from: day))
                    .font(Theme.text(18, .bold))
                    .foregroundStyle(Theme.textPrimary)
                dayStepper
            }
            Spacer(minLength: 0)
            streakBadge
            circleButton("gearshape", label: "Settings") { showingSettings = true }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }

    /// Consecutive days ending today on which anything was logged.
    ///
    /// Food or a weigh-in both count. The streak is there to reward keeping the
    /// model fed, and either one does that — demanding both would break a streak
    /// on a day someone ate carefully but didn't stand on the scale, which
    /// punishes the wrong thing.
    ///
    /// **Today not being logged does not break it.** The count runs from
    /// yesterday in that case, because the day isn't over — a streak that resets
    /// at midnight and only returns after breakfast would spend every morning
    /// lying about the last three weeks.
    ///
    /// Capped at a year of history so this stays bounded on a long-lived store;
    /// nobody is served differently by a 400-day streak than a 365-day one.
    private var loggingStreak: Int {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let earliest = cal.date(byAdding: .day, value: -365, to: today) ?? today

        var logged = Set<Date>()
        for l in nutrition where l.date >= earliest { logged.insert(cal.startOfDay(for: l.date)) }
        for m in metrics where m.date >= earliest { logged.insert(cal.startOfDay(for: m.date)) }
        guard !logged.isEmpty else { return 0 }

        var cursor = today
        if !logged.contains(cursor) {
            guard let yesterday = cal.date(byAdding: .day, value: -1, to: cursor) else { return 0 }
            cursor = yesterday
        }
        var days = 0
        while logged.contains(cursor) {
            days += 1
            guard let previous = cal.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return days
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

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEE d MMM")
        return f
    }()

    /// Steps the whole page a day at a time. Forward stops at today: there is no
    /// data ahead of now, and an empty screen reads as a bug rather than a date.
    private var dayStepper: some View {
        HStack(spacing: 0) {
            stepButton("chevron.left", label: "Previous day", by: -1, enabled: true)
            Rectangle().fill(Theme.hairline).frame(width: 1, height: 16)
            stepButton("chevron.right", label: "Next day", by: 1, enabled: !isToday)
        }
        .background(Capsule().fill(Theme.wash))
        .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
    }

    private func stepButton(_ icon: String, label: String, by days: Int,
                            enabled: Bool) -> some View {
        Button {
            guard let moved = Calendar.current.date(byAdding: .day, value: days, to: day)
            else { return }
            withAnimation(.easeOut(duration: 0.15)) { day = moved }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(enabled ? Theme.textPrimary : Theme.textSecondary.opacity(0.4))
                .frame(width: 32, height: 26)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
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
                    .foregroundStyle(hasData ? Theme.gold : Theme.textSecondary)
            }
        }
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
        cardButton { showingRestingHR = true } content: {
            VStack(spacing: 8) {
                cardLabel("Resting HR")
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(todayVitals?.restingHR.map { "\(Int($0))" } ?? "–")
                        .font(Theme.text(28, .bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("bpm")
                        .font(Theme.text(16))
                        .foregroundStyle(Theme.textSecondary)
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
            Image(systemName: "gearshape")
                .font(.system(size: 20))
                .foregroundStyle(Theme.textPrimary)
        }
        .accessibilityLabel("Settings")
        .sheet(isPresented: $showing) { SettingsView() }
    }
}
