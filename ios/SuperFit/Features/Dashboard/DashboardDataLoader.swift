import Foundation
import SwiftData

/// The bounded persistence snapshot consumed by `DashboardView`.
struct DashboardDataSet {
    let metrics: [BodyMetrics]
    let nutrition: [NutritionLog]
    let estimates: [MetabolicEstimateRecord]
    let recoveries: [RecoveryScoreRecord]
    let strains: [StrainRecord]
    let energy: [DailyEnergy]
    let sleep: [SleepData]
    let vitals: [DailyVitals]
    let workouts: [WorkoutRecord]
}

/// Keeps SwiftData query construction out of the visual dashboard component.
@MainActor
enum DashboardDataLoader {
    static func load(context: ModelContext, day: Date,
                     calendar: Calendar = .current) throws -> DashboardDataSet {
        let selected = DayBounds(day, calendar: calendar)
        let dayStart = selected.start
        let dayEnd = selected.end
        let streakStart = calendar.date(byAdding: .day, value: -365,
                                        to: calendar.startOfDay(for: .now)) ?? dayStart

        let logQuery = FetchDescriptor<NutritionLog>(predicate: #Predicate {
            $0.date >= streakStart || ($0.date >= dayStart && $0.date < dayEnd)
        })
        let nutrition = try context.fetch(logQuery)

        let metricQuery = FetchDescriptor<BodyMetrics>(
            predicate: #Predicate {
                $0.date >= streakStart || ($0.date >= dayStart && $0.date < dayEnd)
            },
            sortBy: [SortDescriptor(\BodyMetrics.date, order: .reverse)])
        var metrics = try context.fetch(metricQuery)

        func appendMetric(_ row: BodyMetrics?) {
            guard let row, !metrics.contains(where: { $0 === row }) else { return }
            metrics.append(row)
        }
        var latestQuery = FetchDescriptor<BodyMetrics>(
            sortBy: [SortDescriptor(\BodyMetrics.date, order: .reverse)])
        latestQuery.fetchLimit = 1
        appendMetric(try context.fetch(latestQuery).first)

        var carriedQuery = FetchDescriptor<BodyMetrics>(
            predicate: #Predicate { $0.date < dayEnd },
            sortBy: [SortDescriptor(\BodyMetrics.date, order: .reverse)])
        carriedQuery.fetchLimit = 1
        appendMetric(try context.fetch(carriedQuery).first)
        metrics.sort { $0.date > $1.date }

        var estimateQuery = FetchDescriptor<MetabolicEstimateRecord>(
            predicate: #Predicate { $0.windowDays == 30 },
            sortBy: [SortDescriptor(\MetabolicEstimateRecord.date, order: .reverse)])
        estimateQuery.fetchLimit = 1
        let estimates = try context.fetch(estimateQuery)

        let recoveryQuery = FetchDescriptor<RecoveryScoreRecord>(
            predicate: #Predicate { $0.date >= dayStart && $0.date < dayEnd },
            sortBy: [SortDescriptor(\RecoveryScoreRecord.date, order: .reverse)])
        let recoveries = try context.fetch(recoveryQuery)

        let strainQuery = FetchDescriptor<StrainRecord>(
            predicate: #Predicate { $0.date >= dayStart && $0.date < dayEnd },
            sortBy: [SortDescriptor(\StrainRecord.date, order: .reverse)])
        let strains = try context.fetch(strainQuery)

        let energyQuery = FetchDescriptor<DailyEnergy>(
            predicate: #Predicate { $0.date >= dayStart && $0.date < dayEnd },
            sortBy: [SortDescriptor(\DailyEnergy.date, order: .reverse)])
        let energy = try context.fetch(energyQuery)

        let sleepQuery = FetchDescriptor<SleepData>(
            predicate: #Predicate { $0.date >= dayStart && $0.date < dayEnd },
            sortBy: [SortDescriptor(\SleepData.date, order: .reverse)])
        var sleep = try context.fetch(sleepQuery)
        var watchSleepQuery = FetchDescriptor<SleepData>(
            predicate: #Predicate { $0.asleepMinutes > 0 },
            sortBy: [SortDescriptor(\SleepData.date, order: .reverse)])
        watchSleepQuery.fetchLimit = 1
        if let proof = try context.fetch(watchSleepQuery).first,
           !sleep.contains(where: { $0 === proof }) {
            sleep.append(proof)
        }

        let vitalQuery = FetchDescriptor<DailyVitals>(
            predicate: #Predicate { $0.date >= dayStart && $0.date < dayEnd },
            sortBy: [SortDescriptor(\DailyVitals.date, order: .reverse)])
        var vitals = try context.fetch(vitalQuery)
        var watchVitalQuery = FetchDescriptor<DailyVitals>(
            predicate: #Predicate { $0.restingHR != nil || $0.hrvSDNN != nil },
            sortBy: [SortDescriptor(\DailyVitals.date, order: .reverse)])
        watchVitalQuery.fetchLimit = 1
        if let proof = try context.fetch(watchVitalQuery).first,
           !vitals.contains(where: { $0 === proof }) {
            vitals.append(proof)
        }

        let workoutQuery = FetchDescriptor<WorkoutRecord>(
            predicate: #Predicate { $0.startedAt >= dayStart && $0.startedAt < dayEnd },
            sortBy: [SortDescriptor(\WorkoutRecord.startedAt, order: .reverse)])
        let workouts = try context.fetch(workoutQuery)

        return DashboardDataSet(metrics: metrics, nutrition: nutrition,
                                estimates: estimates, recoveries: recoveries,
                                strains: strains, energy: energy, sleep: sleep,
                                vitals: vitals, workouts: workouts)
    }
}
