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

    private var profile: UserProfile? { profiles.first }
    private var latestWeight: Double? { metrics.first?.weightKg }

    private var headline: MetabolicEstimateRecord? {
        estimates.first { $0.windowDays == 30 }
    }

    private var macros: MacroTargets? {
        guard let profile, let est = headline, let w = latestWeight else { return nil }
        let tdee = TDEEEstimate(tdeeKcal: est.tdeeKcal, confidence: est.confidence,
                                trendSlopeKgPerWeek: est.trendSlopeKgPerWeek,
                                avgIntakeKcal: est.avgIntakeKcal,
                                smoothedWeightKg: w, windowDays: est.windowDays)
        let target = MetabolismEngine().calorieTarget(tdee: tdee, goal: profile.goal, bodyweightKg: w)
        let override = profile.proteinPerKgOverride > 0 ? profile.proteinPerKgOverride : nil
        return MacroCalculator().targets(kcal: target, goal: profile.goal, bodyweightKg: w,
                                         leanMassKg: metrics.first?.leanMassKg,
                                         proteinPerKg: override)
    }

    private var todayIntake: (kcal: Double, protein: Double) {
        let logs = nutrition.filter { Calendar.current.isDateInToday($0.date) }
        return (logs.reduce(0) { $0 + $1.kcal }, logs.reduce(0) { $0 + $1.proteinG })
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
            ScrollView {
                VStack(spacing: 12) {
                    if let macros {
                        remainingCard(macros: macros)
                    } else {
                        emptyState
                    }
                    if let todayRecovery { recoveryCard(todayRecovery) }
                    activitySleepCard
                    tdeeCard
                }
                .padding(16)
            }
            .navigationTitle("Today")
            .background(Color(.systemGroupedBackground))
            .task { await refresh() }
            .refreshable { await refresh() }
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

    private func remainingCard(macros: MacroTargets) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                metricRow("Calories remaining",
                          value: "\(Int(macros.kcal - todayIntake.kcal))",
                          sub: "of \(Int(macros.kcal)) kcal")
                Divider()
                metricRow("Protein remaining",
                          value: "\(max(0, Int(macros.proteinG - todayIntake.protein))) g",
                          sub: "of \(Int(macros.proteinG)) g")
                HStack(spacing: 16) {
                    macroPill("Carbs", "\(Int(macros.carbG)) g")
                    macroPill("Fat", "\(Int(macros.fatG)) g")
                    macroPill("Fibre", "\(Int(macros.fibreG)) g")
                }
            }
        }
    }

    private func recoveryCard(_ recovery: RecoveryScoreRecord) -> some View {
        Card {
            HStack(spacing: 16) {
                Gauge(value: recovery.score, in: 0...100) {
                    EmptyView()
                } currentValueLabel: {
                    Text("\(Int(recovery.score))")
                        .font(.title3.weight(.semibold)).monospacedDigit()
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(recoveryTint(recovery.score))
                .frame(width: 64, height: 64)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Recovery").font(.subheadline).foregroundStyle(.secondary)
                    Text(recovery.recommendationRaw.isEmpty ? "—" : recovery.recommendationRaw)
                        .font(.headline)
                }
                Spacer()
            }
        }
    }

    private var activitySleepCard: some View {
        Card {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Activity").font(.subheadline).foregroundStyle(.secondary)
                    if let e = todayEnergy {
                        Text("\(e.steps) steps").font(.headline).monospacedDigit()
                        Text("\(Int(e.activeEnergyKcal)) kcal active")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("No data yet").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Divider().frame(height: 44)
                Spacer()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sleep").font(.subheadline).foregroundStyle(.secondary)
                    if let s = lastSleep {
                        Text("\(s.asleepMinutes / 60) h \(s.asleepMinutes % 60) m")
                            .font(.headline).monospacedDigit()
                        Text("\(Int(s.efficiency * 100))% efficiency")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("No data yet").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
        }
    }

    private var tdeeCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Estimated expenditure").font(.subheadline).foregroundStyle(.secondary)
                if let est = headline {
                    Text("\(Int(est.tdeeKcal)) kcal")
                        .font(.title2.weight(.semibold)).monospacedDigit()
                    HStack {
                        Text(String(format: "Trend %+.2f kg/wk", est.trendSlopeKgPerWeek))
                        Spacer()
                        Text("Confidence \(Int(est.confidence * 100))%")
                    }
                    .font(.caption).foregroundStyle(.secondary)
                    if est.confidence < 0.5 {
                        Text("Still learning — log weight daily and mark food days complete for a sharper estimate.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Text("Needs weight entries and complete food days.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var emptyState: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("Set up your day").font(.headline)
                Text("Add your goal in Profile and log your weight to start estimating your energy needs.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private func recoveryTint(_ score: Double) -> Color {
        switch score {
        case 90...: return .green
        case 70..<90: return .teal
        case 50..<70: return .yellow
        default: return .orange
        }
    }

    private func metricRow(_ title: String, value: String, sub: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.subheadline)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(value).font(.title3.weight(.semibold)).monospacedDigit()
                Text(sub).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func macroPill(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.subheadline.weight(.medium)).monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
