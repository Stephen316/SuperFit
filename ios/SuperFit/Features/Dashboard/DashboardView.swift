import SwiftUI
import SwiftData

struct DashboardView: View {
    @Query private var profiles: [UserProfile]
    @Query(sort: \BodyMetrics.date, order: .reverse) private var metrics: [BodyMetrics]
    @Query private var nutrition: [NutritionLog]
    @Query private var statuses: [DayLogStatus]

    private var profile: UserProfile? { profiles.first }
    private var latestWeight: Double? { metrics.first?.weightKg }

    private var estimate: TDEEEstimate? {
        guard let profile, !metrics.isEmpty else { return nil }
        let recs = dailyRecords()
        return MetabolismEngine().estimate(
            records: recs, windowDays: 30,
            prior: .init(sex: profile.sex, ageYears: profile.ageYears,
                         heightCm: profile.heightCm, activity: profile.activity))
    }

    private var macros: MacroTargets? {
        guard let profile, let estimate, let w = latestWeight else { return nil }
        let target = MetabolismEngine().calorieTarget(tdee: estimate, goal: profile.goal, bodyweightKg: w)
        let override = profile.proteinPerKgOverride > 0 ? profile.proteinPerKgOverride : nil
        return MacroCalculator().targets(kcal: target, goal: profile.goal,
                                         bodyweightKg: w,
                                         leanMassKg: metrics.first?.leanMassKg,
                                         proteinPerKg: override)
    }

    private var todayIntake: (kcal: Double, protein: Double) {
        let today = Calendar.current.startOfDay(for: .now)
        let logs = nutrition.filter { Calendar.current.isDate($0.date, inSameDayAs: today) }
        return (logs.reduce(0) { $0 + $1.kcal }, logs.reduce(0) { $0 + $1.proteinG })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    if let macros {
                        remainingCard(macros: macros)
                        tdeeCard
                    } else {
                        emptyState
                    }
                }
                .padding(16)
            }
            .navigationTitle("Today")
            .background(Color(.systemGroupedBackground))
        }
    }

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

    private var tdeeCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Estimated expenditure").font(.subheadline).foregroundStyle(.secondary)
                if let estimate {
                    Text("\(Int(estimate.tdeeKcal)) kcal")
                        .font(.title2.weight(.semibold)).monospacedDigit()
                    HStack {
                        Text(String(format: "Trend %+.2f kg/wk", estimate.trendSlopeKgPerWeek))
                        Spacer()
                        Text("Confidence \(Int(estimate.confidence * 100))%")
                    }
                    .font(.caption).foregroundStyle(.secondary)
                    if estimate.confidence < 0.5 {
                        Text("Still learning — keep logging weight and food for a sharper estimate.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
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

    private func dailyRecords() -> [DailyRecord] {
        MetabolicRecordAssembler.dailyRecords(logs: nutrition, metrics: metrics, statuses: statuses)
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
