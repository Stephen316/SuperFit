import Testing
import Foundation
import SwiftData
@testable import SuperFit

struct HealthDataReconciliationTests {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Dublin")!
        return cal
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 8, day: day,
                                           hour: hour, minute: minute))!
    }

    @Test func overnightStagesAreStoredTogetherOnTheWakeDay() throws {
        let intervals = [
            SleepStageInterval(start: date(8, 22, 30), end: date(8, 23, 30),
                               stage: .core, sourceID: "watch"),
            SleepStageInterval(start: date(8, 23, 30), end: date(9, 1),
                               stage: .deep, sourceID: "watch"),
            SleepStageInterval(start: date(9, 1), end: date(9, 4),
                               stage: .core, sourceID: "watch"),
            SleepStageInterval(start: date(9, 4), end: date(9, 6, 30),
                               stage: .rem, sourceID: "watch")
        ]

        let night = try #require(SleepIntervalReconciler.reconcile(
            intervals, calendar: calendar).first)
        #expect(calendar.isDate(night.day, inSameDayAs: date(9, 0)))
        #expect(night.asleepMinutes == 480)
        #expect(night.coreMinutes == 240)
        #expect(night.deepMinutes == 90)
        #expect(night.remMinutes == 150)
    }

    @Test func overlappingPhoneAndWatchSleepIsUnionedNotSummed() throws {
        let start = date(8, 22)
        let end = date(9, 6)
        let intervals = [
            SleepStageInterval(start: start, end: end,
                               stage: .asleepUnspecified, sourceID: "phone"),
            SleepStageInterval(start: start, end: date(9, 2),
                               stage: .core, sourceID: "watch"),
            SleepStageInterval(start: date(9, 2), end: date(9, 4),
                               stage: .deep, sourceID: "watch"),
            SleepStageInterval(start: date(9, 4), end: end,
                               stage: .rem, sourceID: "watch"),
            SleepStageInterval(start: start, end: end,
                               stage: .inBed, sourceID: "phone")
        ]

        let night = try #require(SleepIntervalReconciler.reconcile(
            intervals, calendar: calendar).first)
        #expect(night.asleepMinutes == 480)
        #expect(night.inBedMinutes == 480)
        #expect(night.coreMinutes + night.deepMinutes + night.remMinutes == 480)
    }
}

@MainActor
struct CyclicalPatternDuplicateTests {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(AppSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        return ModelContext(container)
    }

    @Test func duplicateActiveMarkersDoNotCrashRecoveryAndAreConsolidated() throws {
        let context = try makeContext()
        let profile = UserProfile()
        profile.sex = .female
        context.insert(profile)
        context.insert(DailyVitals(date: .now))

        for offset in [0.0, 60.0] {
            let row = CyclicalPatternRecord(marker: "hrv")
            row.detectedAt = .now.addingTimeInterval(offset)
            row.periodDays = 28
            row.cyclesObserved = 6
            row.profile = Array(repeating: 0, count: 28)
            row.isActive = true
            context.insert(row)
        }
        try context.save()

        let aggregation = AggregationService(context: context)
        aggregation.upsertTodayRecovery() // Exercises duplicate-safe active lookup.
        aggregation.refreshCyclicalPatterns() // Removes the stale duplicate.

        let patterns = try context.fetch(FetchDescriptor<CyclicalPatternRecord>())
            .filter { $0.markerRaw == "hrv" }
        #expect(patterns.count == 1)
        #expect(patterns.first?.isActive == false)
    }
}
