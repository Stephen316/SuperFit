import Foundation
import SwiftData
import Testing
@testable import SuperFit

@MainActor
struct DashboardDataLoaderTests {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(AppSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        return ModelContext(container)
    }

    @Test func selectedOldDayIsLoadedAlongsideStreakWindowAndCarryForwardWeight() throws {
        let context = try makeContext()
        let calendar = Calendar(identifier: .gregorian)
        let selectedDay = calendar.date(byAdding: .day, value: -500,
                                        to: calendar.startOfDay(for: .now))!
        let oldLog = NutritionLog(date: selectedDay.addingTimeInterval(3_600), meal: .breakfast)
        let recentLog = NutritionLog(date: .now, meal: .lunch)
        let carriedWeight = BodyMetrics(date: selectedDay.addingTimeInterval(-86_400),
                                        weightKg: 80)
        let latestWeight = BodyMetrics(date: .now, weightKg: 79)
        context.insert(oldLog)
        context.insert(recentLog)
        context.insert(carriedWeight)
        context.insert(latestWeight)
        try context.save()

        let loaded = try DashboardDataLoader.load(context: context,
                                                   day: selectedDay,
                                                   calendar: calendar)

        #expect(Set(loaded.nutrition.map(\.id)) == Set([oldLog.id, recentLog.id]))
        #expect(loaded.metrics.contains { $0.id == carriedWeight.id })
        #expect(loaded.metrics.contains { $0.id == latestWeight.id })
    }
}
