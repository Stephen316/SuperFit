import SwiftUI
import SwiftData
import Charts

/// Every trend the app can draw, in one place.
///
/// The app's whole claim is that it *measures* expenditure rather than guessing
/// it — and until now it never showed that measurement over time. Adaptive
/// thermogenesis during a cut, the thing this engine exists to detect, was
/// invisible.
struct HistoryView: View {
    @AppStorage(UnitSystem.storageKey) private var unitsRaw = UnitSystem.metric.rawValue

    @Query private var profiles: [UserProfile]
    @Query private var metrics: [BodyMetrics]
    @Query private var logs: [NutritionLog]
    @Query private var energy: [DailyEnergy]
    @Query private var supplements: [Supplement]
    @Query private var supplementEntries: [SupplementEntry]
    @Query private var recoveries: [RecoveryScoreRecord]
    @Query private var vitals: [DailyVitals]
    @Query private var sleep: [SleepData]
    @Query private var sessions: [TrainingSession]
    @Query private var exercises: [Exercise]
    @Query private var workouts: [WorkoutRecord]

    @State private var range = HistoryRange.quarter
    @State private var selectedMuscle = MuscleGroup.chest
    @State private var selectedExerciseID: UUID?
    @State private var selectedActivity: WorkoutActivity?
    @State private var showingRate = false

    init() {
        // The largest selectable range is one year. Metabolism needs the thirty
        // preceding days to calculate the first visible point, hence the buffer.
        let chartCutoff = Calendar.current.date(byAdding: .day, value: -365, to: .now) ?? .now
        let metabolismCutoff = Calendar.current.date(byAdding: .day, value: -396, to: .now) ?? .now
        _metrics = Query(filter: #Predicate { $0.date >= metabolismCutoff },
                         sort: \BodyMetrics.date)
        _logs = Query(filter: #Predicate { $0.date >= metabolismCutoff })
        _energy = Query(filter: #Predicate { $0.date >= metabolismCutoff })
        _recoveries = Query(filter: #Predicate { $0.date >= chartCutoff },
                            sort: \RecoveryScoreRecord.date)
        _vitals = Query(filter: #Predicate { $0.date >= chartCutoff },
                        sort: \DailyVitals.date)
        _sleep = Query(filter: #Predicate { $0.date >= chartCutoff },
                       sort: \SleepData.date)
        _sessions = Query(filter: #Predicate { $0.startedAt >= chartCutoff })
        _workouts = Query(filter: #Predicate { $0.startedAt >= chartCutoff },
                          sort: \WorkoutRecord.startedAt)
    }

    private var units: UnitSystem { UnitSystem(rawValue: unitsRaw) ?? .metric }
    private var start: Date { range.start }

    var body: some View {
        ZStack {
            FeatureBackground()
            ScrollView {
                LazyVStack(spacing: 14) {
                    rangePicker
                    energyCard
                    weightCard
                    rateDisclosure
                    if !compositionPoints.isEmpty { compositionCard }
                    recoveryCard
                    vitalsCard
                    stepsCard
                    activeEnergyCard
                    sleepCard
                    sleepStagesCard
                    bedtimeCard
                    if !distanceActivities.isEmpty { distanceCard }
                    volumeCard
                    trainingLoadCard
                    if selectedExerciseID != nil { strengthCard }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Trends")
        .navigationBarTitleDisplayMode(.inline)
        .themedChrome()
        .task {
            if selectedExerciseID == nil { selectedExerciseID = mostTrainedExerciseID }
            if selectedActivity == nil { selectedActivity = distanceActivities.first }
        }
    }

    private var rangePicker: some View {
        FeatureTabControl(
            options: HistoryRange.allCases.map { ($0, $0.label) },
            selection: $range)
    }

    // MARK: - Energy

    private var dailyRecords: [DailyRecord] {
        MetabolicRecordAssembler.dailyRecords(
            logs: logs, metrics: metrics,
            supplementKcal: SupplementIntake.dailyKcal(
                entries: supplementEntries, supplements: supplements,
                from: start, to: .now))
    }

    private var tdeeBands: [HistoryBand] {
        guard let profile = profiles.first else { return [] }
        let prior = MetabolismEngine.Prior(
            sex: profile.sex, ageYears: profile.ageYears,
            heightCm: profile.heightCm, activity: profile.activity,
            avgActiveEnergyKcal: MetabolicRecordAssembler.avgActiveEnergy(energy: energy),
            leanMassKg: BodyComposition.recentLeanMassKg(metrics))
        return HistorySeries.tdee(records: dailyRecords, prior: prior,
                                  from: start, to: .now)
    }

    private var intakePoints: [HistoryPoint] {
        HistorySeries.intake(records: dailyRecords).filter { $0.date >= start }
    }

    /// Expenditure and intake on one axis, with the gap between them shaded.
    ///
    /// Two separate charts made the reader subtract by eye to answer the only
    /// question that matters — am I actually in a deficit — so they're one card
    /// with the balance as the headline.
    private var energyCard: some View {
        let bands = tdeeBands
        let intake = intakePoints
        let intakeMean = HistorySeries.rollingMean(intake)
        let balance = HistorySeries.energyBalance(intake: intake, tdee: bands)
        let average = balance.isEmpty ? nil
            : balance.reduce(0) { $0 + $1.value } / Double(balance.count)

        return HistoryChartCard(
            title: "Energy balance",
            headline: average.map { "\($0 >= 0 ? "+" : "")\(Int($0.rounded())) kcal/day" },
            change: bands.last.map { "burning \(Int($0.value))" },
            height: 190,
            yLabel: { "\(Int($0))" },
            content: {
                // The gap is the story; the lines just bound it.
                ForEach(balancePairs(bands: bands, intake: intakeMean)) { pair in
                    AreaMark(x: .value("Date", pair.date),
                             yStart: .value("Intake", pair.intake),
                             yEnd: .value("TDEE", pair.tdee))
                        .foregroundStyle(pair.intake < pair.tdee
                                         ? Color.green.opacity(0.16)
                                         : Color.orange.opacity(0.16))
                }
                ForEach(bands) { band in
                    LineMark(x: .value("Date", band.date),
                             y: .value("Expenditure", band.value),
                             series: .value("Series", "Expenditure"))
                        .foregroundStyle(Theme.gold)
                        .interpolationMethod(.monotone)
                }
                if range.showsDailyPoints {
                    ForEach(intake) { p in
                        PointMark(x: .value("Date", p.date), y: .value("Intake", p.value))
                            .foregroundStyle(Theme.textSecondary.opacity(0.55))
                            .symbolSize(12)
                    }
                }
                ForEach(intakeMean) { p in
                    LineMark(x: .value("Date", p.date),
                             y: .value("Intake", p.value),
                             series: .value("Series", "Intake"))
                        .foregroundStyle(Theme.textPrimary)
                        .interpolationMethod(.monotone)
                }
            },
            isEmpty: bands.count < 2 || intakeMean.isEmpty,
            emptyMessage: "Log food and weigh in for about a week to see your deficit or surplus."
        )
    }

    /// Days where both series exist, so the shaded gap can't straddle a hole.
    private struct BalancePair: Identifiable {
        let date: Date
        let tdee: Double
        let intake: Double
        var id: Date { date }
    }

    private func balancePairs(bands: [HistoryBand],
                              intake: [HistoryPoint]) -> [BalancePair] {
        let cal = Calendar.current
        let byDay = Dictionary(intake.map { (cal.startOfDay(for: $0.date), $0.value) },
                               uniquingKeysWith: { a, _ in a })
        return bands.compactMap { band in
            byDay[cal.startOfDay(for: band.date)].map {
                BalancePair(date: band.date, tdee: band.value, intake: $0)
            }
        }
    }

    // MARK: - Body

    /// One point per day, at the lowest reading — the same value every
    /// calculation uses. See `DailyWeight`.
    private var weightPoints: [HistoryPoint] {
        DailyWeight.byDay(metrics.filter { $0.date >= start },
                          date: \.date, weightKg: \.weightKg, calendar: .current)
            .map { HistoryPoint(date: $0.key, value: units.displayWeight($0.value)) }
            .sorted { $0.date < $1.date }
    }

    /// Also one per day: every row of a day now carries that day's trend, so
    /// mapping each row would stack identical points on one date.
    private var trendPoints: [HistoryPoint] {
        DailyWeight.byDay(metrics.filter { $0.date >= start },
                          date: \.date, weightKg: \.trendWeightKg, calendar: .current)
            .map { HistoryPoint(date: $0.key, value: units.displayWeight($0.value)) }
            .sorted { $0.date < $1.date }
    }

    private var weightCard: some View {
        let points = weightPoints
        let trend = trendPoints
        let delta = HistorySeries.change(trend.isEmpty ? points : trend)
        return HistoryChartCard(
            title: "Weight",
            headline: trend.last.map { String(format: "%.1f %@", $0.value, units.weightUnit) },
            change: delta.map { String(format: "%+.1f %@", $0, units.weightUnit) },
            yLabel: { String(format: "%.0f", $0) },
            content: {
                ForEach(points) { p in
                    PointMark(x: .value("Date", p.date), y: .value("Weight", p.value))
                        .foregroundStyle(Theme.textSecondary.opacity(0.6))
                        .symbolSize(14)
                }
                ForEach(trend) { p in
                    LineMark(x: .value("Date", p.date), y: .value("Trend", p.value))
                        .foregroundStyle(Theme.gold)
                        .interpolationMethod(.monotone)
                }
            },
            isEmpty: points.count < 2,
            emptyMessage: "Log a few weigh-ins to see your trend."
        )
    }

    /// Collapsed by default: the rate is a second-order read on the same data,
    /// useful when you go looking for it and clutter when you don't.
    private var rateDisclosure: some View {
        DisclosureGroup(isExpanded: $showingRate) {
            rateCard.padding(.top, 10)
        } label: {
            HStack {
                Text("Rate of change")
                    .font(Theme.font(15))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                if let latest = ratePoints.last {
                    Text(units.weightDeltaString(latest.value))
                        .font(Theme.font(13))
                        .monospacedDigit()
                        .foregroundStyle(rateIsSafe(latest.value) ? Theme.textSecondary : .orange)
                }
            }
        }
        .tint(Theme.gold)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .featurePanel()
    }

    private var ratePoints: [HistoryPoint] {
        guard let profile = profiles.first else { return [] }
        let prior = MetabolismEngine.Prior(
            sex: profile.sex, ageYears: profile.ageYears,
            heightCm: profile.heightCm, activity: profile.activity,
            leanMassKg: BodyComposition.recentLeanMassKg(metrics))
        return HistorySeries.rateOfChange(records: dailyRecords, prior: prior,
                                          from: start, to: .now)
    }

    private var guardrails: (loss: Double, gain: Double) {
        HistorySeries.rateGuardrails(bodyweightKg: metrics.last?.basisWeightKg ?? 80)
    }

    private func rateIsSafe(_ kgPerWeek: Double) -> Bool {
        kgPerWeek >= guardrails.loss && kgPerWeek <= guardrails.gain
    }

    /// The shaded band is the same 1%/0.5% of bodyweight the calorie target is
    /// clamped to, so the chart and the target agree on what "too fast" means.
    private var rateCard: some View {
        let rawPoints = ratePoints
        let points = rawPoints.map {
            HistoryPoint(date: $0.date, value: units.displayWeight($0.value))
        }
        let rails = guardrails
        return HistoryChartCard(
            title: "Weekly change",
            headline: rawPoints.last.map { units.weightDeltaString($0.value) },
            height: 150,
            yLabel: { String(format: "%+.1f", $0) },
            content: {
                RectangleMark(
                    xStart: .value("Start", start),
                    xEnd: .value("End", Date.now),
                    yStart: .value("Max loss", units.displayWeight(rails.loss)),
                    yEnd: .value("Max gain", units.displayWeight(rails.gain)))
                    .foregroundStyle(Color.green.opacity(0.10))
                RuleMark(y: .value("Stable", 0))
                    .lineStyle(.init(lineWidth: 1))
                    .foregroundStyle(Theme.divider)
                ForEach(points) { p in
                    LineMark(x: .value("Date", p.date), y: .value("kg/week", p.value))
                        .foregroundStyle(Theme.gold)
                        .interpolationMethod(.monotone)
                }
            },
            isEmpty: points.count < 2,
            emptyMessage: "Weigh in across a couple of weeks to see how your rate is moving."
        )
    }

    private var compositionPoints: [HistoryPoint] {
        metrics.filter { $0.date >= start }
            .compactMap { m in m.leanMassKg.map {
                HistoryPoint(date: m.date, value: units.displayWeight($0)) } }
    }

    /// Lean mass against total weight — the one chart that actually shows
    /// recomposition, where the scale alone can't.
    private var compositionCard: some View {
        let lean = compositionPoints
        let total = weightPoints
        return HistoryChartCard(
            title: "Lean mass vs total weight",
            headline: lean.last.map { String(format: "%.1f %@ lean", $0.value, units.weightUnit) },
            change: HistorySeries.change(lean).map { String(format: "%+.1f %@", $0, units.weightUnit) },
            changeIsGood: HistorySeries.change(lean).map { $0 >= 0 },
            yLabel: { String(format: "%.0f", $0) },
            content: {
                ForEach(total) { p in
                    LineMark(x: .value("Date", p.date), y: .value("Weight", p.value),
                             series: .value("Series", "Total"))
                        .foregroundStyle(Theme.textSecondary.opacity(0.75))
                        .interpolationMethod(.monotone)
                }
                ForEach(lean) { p in
                    LineMark(x: .value("Date", p.date), y: .value("Lean", p.value),
                             series: .value("Series", "Lean"))
                        .foregroundStyle(Theme.gold)
                        .interpolationMethod(.monotone)
                }
            },
            isEmpty: lean.count < 2
        )
    }

    // MARK: - Recovery

    private var recoveryPoints: [HistoryPoint] {
        recoveries.filter { $0.date >= start && $0.dataCompleteness > 0 }
            .map { HistoryPoint(date: $0.date, value: $0.score) }
    }

    private var recoveryCard: some View {
        let points = recoveryPoints
        let mean = HistorySeries.rollingMean(points)
        return HistoryChartCard(
            title: "Recovery",
            headline: points.last.map { "\(Int($0.value))" },
            change: HistorySeries.change(points).map { "\($0 >= 0 ? "+" : "")\(Int($0))" },
            changeIsGood: HistorySeries.change(points).map { $0 >= 0 },
            content: {
                RuleMark(y: .value("Normal", 70))
                    .lineStyle(.init(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(Theme.divider)
                ForEach(points) { p in
                    PointMark(x: .value("Date", p.date), y: .value("Score", p.value))
                        .foregroundStyle(Theme.textSecondary.opacity(0.6))
                        .symbolSize(14)
                }
                ForEach(mean) { p in
                    LineMark(x: .value("Date", p.date), y: .value("Average", p.value))
                        .foregroundStyle(Theme.gold)
                        .interpolationMethod(.monotone)
                }
            },
            isEmpty: points.count < 2,
            emptyMessage: "Recovery needs sleep or heart data from Apple Health."
        )
    }

    private var vitalsCard: some View {
        let hrv = HistorySeries.daily(vitals.filter { $0.date >= start },
                                      date: \.date, value: \.hrvSDNN)
        let rhr = HistorySeries.daily(vitals.filter { $0.date >= start },
                                      date: \.date, value: \.restingHR)
        return HistoryChartCard(
            title: "HRV and resting heart rate",
            headline: hrv.last.map { "\(Int($0.value)) ms HRV" },
            content: {
                ForEach(HistorySeries.rollingMean(hrv)) { p in
                    LineMark(x: .value("Date", p.date), y: .value("HRV", p.value),
                             series: .value("Series", "HRV"))
                        .foregroundStyle(Theme.gold)
                        .interpolationMethod(.monotone)
                }
                ForEach(HistorySeries.rollingMean(rhr)) { p in
                    LineMark(x: .value("Date", p.date), y: .value("RHR", p.value),
                             series: .value("Series", "Resting HR"))
                        .foregroundStyle(Theme.textSecondary)
                        .interpolationMethod(.monotone)
                }
            },
            isEmpty: hrv.count < 8 && rhr.count < 8,
            emptyMessage: "Needs about a week of heart data from a watch."
        )
    }

    private var sleepCard: some View {
        let points = sleep.filter { $0.date >= start && $0.asleepMinutes > 0 }
            .map { HistoryPoint(date: $0.date, value: Double($0.asleepMinutes) / 60) }
        let mean = HistorySeries.rollingMean(points)
        return HistoryChartCard(
            title: "Sleep",
            headline: mean.last.map { String(format: "%.1f h average", $0.value) },
            yLabel: { "\(Int($0))h" },
            content: {
                RuleMark(y: .value("Need", Double(SleepAnalytics.defaultNeedMinutes) / 60))
                    .lineStyle(.init(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(Theme.divider)
                if range.showsDailyPoints {
                    ForEach(points) { p in
                        BarMark(x: .value("Date", p.date, unit: .day),
                                y: .value("Hours", p.value))
                            .foregroundStyle(Theme.gold.opacity(0.3))
                    }
                }
                ForEach(mean) { p in
                    LineMark(x: .value("Date", p.date), y: .value("Average", p.value))
                        .foregroundStyle(Theme.gold)
                        .interpolationMethod(.monotone)
                }
            },
            isEmpty: range.showsDailyPoints ? points.count < 2 : mean.isEmpty,
            emptyMessage: "No sleep recorded in this period."
        )
    }

    // MARK: - Cardio

    private var cardioRecords: [CardioDistanceRecord] {
        workouts.map {
            CardioDistanceRecord(date: $0.startedAt, activity: $0.activity,
                                 distanceMetres: $0.distanceMetres ?? 0)
        }
    }

    /// Only activities with a logged distance, so the picker never offers an
    /// activity with nothing to plot.
    private var distanceActivities: [WorkoutActivity] {
        HistorySeries.loggedDistanceActivities(cardioRecords, from: start, to: .now)
    }

    /// Per-session distance for the chosen activity — the trend that says whether
    /// the runs (or swims, rides) are getting longer.
    private var distanceCard: some View {
        let activity = selectedActivity ?? distanceActivities.first ?? .running
        let points = HistorySeries.distanceTrend(cardioRecords, activity: activity,
                                                 from: start, to: .now)
            .map { HistoryPoint(date: $0.date, value: units.displayDistance($0.value)) }
        let delta = HistorySeries.change(points, edgeDays: 14)

        return VStack(alignment: .leading, spacing: 10) {
            Picker("Activity", selection: $selectedActivity) {
                ForEach(distanceActivities, id: \.self) { a in
                    Text(a.displayName).tag(Optional(a))
                }
            }
            .pickerStyle(.menu)
            .tint(Theme.gold)

            HistoryChartCard(
                title: "Distance — \(activity.displayName)",
                headline: points.last.map {
                    String(format: "%.2f %@", $0.value, units.distanceUnit) },
                change: delta.map { String(format: "%+.2f %@", $0, units.distanceUnit) },
                changeIsGood: delta.map { $0 >= 0 },
                yLabel: { String(format: "%.1f", $0) },
                content: {
                    ForEach(points) { p in
                        LineMark(x: .value("Date", p.date), y: .value("Distance", p.value))
                            .foregroundStyle(Theme.gold)
                            .interpolationMethod(.monotone)
                        PointMark(x: .value("Date", p.date), y: .value("Distance", p.value))
                            .foregroundStyle(Theme.gold)
                            .symbolSize(20)
                    }
                },
                isEmpty: points.count < 2,
                emptyMessage: "Log a couple of \(activity.displayName.lowercased()) sessions with distance to see a trend."
            )
        }
    }

    // MARK: - Fundamental trends (#11)

    private var stepsCard: some View {
        let points = HistorySeries.daily(energy.filter { $0.date >= start && $0.steps > 0 },
                                         date: \.date, value: { Double($0.steps) })
        let mean = HistorySeries.rollingMean(points)
        return HistoryChartCard(
            title: "Steps",
            headline: mean.last.map { "\(Int($0.value.rounded())) /day avg" },
            content: {
                if range.showsDailyPoints {
                    ForEach(points) { p in
                        BarMark(x: .value("Date", p.date, unit: .day), y: .value("Steps", p.value))
                            .foregroundStyle(Theme.gold.opacity(0.3))
                    }
                }
                ForEach(mean) { p in
                    LineMark(x: .value("Date", p.date), y: .value("Average", p.value))
                        .foregroundStyle(Theme.gold).interpolationMethod(.monotone)
                }
            },
            isEmpty: points.count < 2,
            emptyMessage: "No step data in this period."
        )
    }

    private var activeEnergyCard: some View {
        let points = HistorySeries.daily(energy.filter { $0.date >= start && $0.activeEnergyKcal > 0 },
                                         date: \.date, value: { $0.activeEnergyKcal })
        let mean = HistorySeries.rollingMean(points)
        return HistoryChartCard(
            title: "Active energy",
            headline: mean.last.map { "\(Int($0.value.rounded())) kcal/day avg" },
            content: {
                if range.showsDailyPoints {
                    ForEach(points) { p in
                        BarMark(x: .value("Date", p.date, unit: .day), y: .value("kcal", p.value))
                            .foregroundStyle(Theme.strain.opacity(0.3))
                    }
                }
                ForEach(mean) { p in
                    LineMark(x: .value("Date", p.date), y: .value("Average", p.value))
                        .foregroundStyle(Theme.strain).interpolationMethod(.monotone)
                }
            },
            isEmpty: points.count < 2,
            emptyMessage: "No active-energy data in this period."
        )
    }

    /// Deep + REM are what recovery leans on, so stages are stacked rather than
    /// hidden inside a single "asleep" total.
    private struct StageArea: Identifiable {
        let date: Date, stage: String, hours: Double
        var id: String { "\(date.timeIntervalSince1970)-\(stage)" }
    }

    private var sleepStagesCard: some View {
        let nights = sleep.filter { $0.date >= start && $0.asleepMinutes > 0 }
            .sorted { $0.date < $1.date }
        let areas = nights.flatMap { n in
            [("Deep", n.deepMinutes), ("REM", n.remMinutes), ("Core", n.coreMinutes)]
                .map { StageArea(date: n.date, stage: $0.0, hours: Double($0.1) / 60) }
        }
        return HistoryChartCard(
            title: "Sleep stages",
            headline: nights.last.map {
                String(format: "%.1f h deep + REM", Double($0.deepMinutes + $0.remMinutes) / 60) },
            yLabel: { "\(Int($0))h" },
            content: {
                ForEach(areas) { seg in
                    AreaMark(x: .value("Date", seg.date), y: .value("Hours", seg.hours))
                        .foregroundStyle(by: .value("Stage", seg.stage))
                }
            },
            isEmpty: nights.count < 2,
            emptyMessage: "Needs a few nights of stage data from a watch."
        )
    }

    private var bedtimePoints: [HistoryPoint] {
        sleep.filter { $0.date >= start }
            .compactMap { s in s.bedtime.map {
                HistoryPoint(date: s.date, value: HistorySeries.bedtimeOffsetMinutes($0)) } }
            .sorted { $0.date < $1.date }
    }

    /// Bedtime plotted per night with its rolling mean; the spread *is* the
    /// consistency the SD headline names. See `HistorySeries.bedtimeOffsetMinutes`.
    private var bedtimeCard: some View {
        let points = bedtimePoints
        let sd = HistorySeries.standardDeviation(points.map(\.value))
        return HistoryChartCard(
            title: "Bedtime consistency",
            headline: sd.map { "±\(Int($0.rounded())) min" },
            yLabel: { clockFromOffset($0) },
            content: {
                ForEach(points) { p in
                    PointMark(x: .value("Date", p.date), y: .value("Bedtime", p.value))
                        .foregroundStyle(Theme.sleep.opacity(0.6)).symbolSize(14)
                }
                ForEach(HistorySeries.rollingMean(points)) { p in
                    LineMark(x: .value("Date", p.date), y: .value("Average", p.value))
                        .foregroundStyle(Theme.sleep).interpolationMethod(.monotone)
                }
            },
            isEmpty: points.count < 2,
            emptyMessage: "Needs a few nights with a recorded bedtime."
        )
    }

    private func clockFromOffset(_ offset: Double) -> String {
        let m = ((Int(offset.rounded()) % 1440) + 1440) % 1440
        return String(format: "%02d:%02d", m / 60, m % 60)
    }

    /// Overall weekly load — tonnage moved and how often — complementing the
    /// per-muscle set volume below. Frequency rides in the corner metric.
    private var trainingLoadCard: some View {
        let tonnage = HistorySeries.weeklyTonnage(records: liftRecords, from: start, to: .now)
            .map { HistoryPoint(date: $0.date, value: units.displayWeight($0.value)) }
        let sessions = HistorySeries.weeklySessionCount(records: liftRecords, from: start, to: .now)
        let lastSessions = Int(sessions.last?.value ?? 0)
        return HistoryChartCard(
            title: "Training load",
            headline: tonnage.last.map {
                String(format: "%.0f %@ this week", $0.value, units.weightUnit) },
            change: "\(lastSessions) session\(lastSessions == 1 ? "" : "s")/wk",
            yLabel: { "\(Int($0))" },
            content: {
                ForEach(tonnage) { p in
                    BarMark(x: .value("Week", p.date, unit: .weekOfYear),
                            y: .value("Tonnage", p.value))
                        .foregroundStyle(Theme.gold.opacity(0.8))
                }
            },
            isEmpty: tonnage.allSatisfy { $0.value == 0 },
            emptyMessage: "Log some weighted sets to see weekly tonnage."
        )
    }

    // MARK: - Training

    private var liftRecords: [LiftRecord] {
        let fractions = Dictionary(exercises.map { ($0.id, $0.bodyweightFraction) },
                                   uniquingKeysWith: { a, _ in a })
        return TrainingRecords.completed(sessions, fractions: fractions)
    }

    private var volumeCard: some View {
        let tension = Dictionary(exercises.map { ($0.id, $0.tension) },
                                 uniquingKeysWith: { a, _ in a })
        let points = HistorySeries.weeklySets(records: liftRecords, muscles: tension,
                                              muscle: selectedMuscle, from: start, to: .now)
        return VStack(alignment: .leading, spacing: 10) {
            Picker("Muscle", selection: $selectedMuscle) {
                ForEach(MuscleGroup.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.menu)
            .tint(Theme.gold)

            HistoryChartCard(
                title: "Weekly sets — \(selectedMuscle.displayName)",
                headline: points.last.map { "\(Int($0.value.rounded())) sets" },
                yLabel: { "\(Int($0))" },
                content: {
                    RectangleMark(
                        xStart: .value("Start", start),
                        xEnd: .value("End", Date.now),
                        // The recommended band for *this* muscle — a shared one
                        // would be wrong for two thirds of the body.
                        yStart: .value("Low", selectedMuscle.weeklyTargets.productiveFrom),
                        yEnd: .value("High", selectedMuscle.weeklyTargets.highFrom))
                        .foregroundStyle(Theme.gold.opacity(0.10))
                    ForEach(points) { p in
                        BarMark(x: .value("Week", p.date, unit: .weekOfYear),
                                y: .value("Sets", p.value))
                            .foregroundStyle(Theme.gold.opacity(0.8))
                    }
                },
                isEmpty: points.allSatisfy { $0.value == 0 },
                emptyMessage: "No sets logged for this muscle in this period."
            )
        }
    }

    private var mostTrainedExerciseID: UUID? {
        var counts: [UUID: Int] = [:]
        for record in liftRecords where !record.isWarmup {
            counts[record.exerciseID, default: 0] += 1
        }
        return counts.max { $0.value < $1.value }?.key
    }

    private var strengthCard: some View {
        let id = selectedExerciseID
        let points = id.map {
            HistorySeries.e1RMHistory(records: liftRecords, exerciseID: $0,
                                      from: start, to: .now)
        } ?? []
        let display = points.map {
            HistoryPoint(date: $0.date, value: units.displayWeight($0.value))
        }
        let name = exercises.first { $0.id == id }?.name ?? "Exercise"

        return VStack(alignment: .leading, spacing: 10) {
            Picker("Exercise", selection: $selectedExerciseID) {
                ForEach(trainedExercises, id: \.id) { e in
                    Text(e.name).tag(Optional(e.id))
                }
            }
            .pickerStyle(.menu)
            .tint(Theme.gold)

            HistoryChartCard(
                title: "Estimated 1RM — \(name)",
                headline: display.last.map {
                    String(format: "%.0f %@", $0.value, units.weightUnit) },
                change: HistorySeries.change(display, edgeDays: 2).map {
                    String(format: "%+.0f %@", $0, units.weightUnit) },
                changeIsGood: HistorySeries.change(display, edgeDays: 2).map { $0 >= 0 },
                yLabel: { String(format: "%.0f", $0) },
                content: {
                    ForEach(display) { p in
                        LineMark(x: .value("Week", p.date), y: .value("e1RM", p.value))
                            .foregroundStyle(Theme.gold)
                            .interpolationMethod(.monotone)
                        PointMark(x: .value("Week", p.date), y: .value("e1RM", p.value))
                            .foregroundStyle(Theme.gold)
                            .symbolSize(20)
                    }
                },
                isEmpty: display.count < 2,
                emptyMessage: "Train this lift on two separate weeks to see a trend."
            )
        }
    }

    /// Only lifts with logged work — the full 56-item catalog in a picker is
    /// unusable.
    private var trainedExercises: [Exercise] {
        let trained = Set(liftRecords.filter { !$0.isWarmup }.map(\.exerciseID))
        return exercises.filter { trained.contains($0.id) }.sorted { $0.name < $1.name }
    }
}
