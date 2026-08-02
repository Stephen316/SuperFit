import Testing
import Foundation
import SwiftData
@testable import SuperFit

/// One day, several readings, one number. The rule is a product decision, so it
/// is pinned rather than left to whichever call site happens to run.
struct DailyWeightTests {

    private let cal = Calendar(identifier: .gregorian)

    private struct Reading { let date: Date; let kg: Double? }

    @Test func theLowestReadingWins() {
        #expect(DailyWeight.resolve([80.5, 80.1, 81.0]) == 80.1)
        #expect(DailyWeight.resolve([79.4]) == 79.4)
        #expect(DailyWeight.resolve([]) == nil)
    }

    /// The point of the rule: a day's value must not move because somebody
    /// weighed themselves a second time after dinner. Under the mean it did.
    @Test func anExtraEveningReadingCannotMoveTheDay() {
        let morningOnly = [80.0]
        let morningAndEvening = [80.0, 81.4]
        #expect(DailyWeight.resolve(morningOnly) == DailyWeight.resolve(morningAndEvening))

        let meanOnly = morningOnly.reduce(0, +) / 1
        let meanBoth = morningAndEvening.reduce(0, +) / 2
        #expect(meanOnly != meanBoth, "the mean is what this rule replaces")
    }

    @Test func readingsGroupByCalendarDay() {
        let today = cal.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
        let readings = [
            Reading(date: today.addingTimeInterval(7 * 3600), kg: 80.4),
            Reading(date: today.addingTimeInterval(20 * 3600), kg: 81.2),
            Reading(date: yesterday.addingTimeInterval(8 * 3600), kg: 80.9),
        ]
        let byDay = DailyWeight.byDay(readings, date: \.date, weightKg: \.kg, calendar: cal)
        #expect(byDay.count == 2)
        #expect(byDay[today] == 80.4)
        #expect(byDay[yesterday] == 80.9)
    }

    /// A day whose only readings are missing produces no entry at all, rather
    /// than a zero that would read as a 80 kg loss.
    @Test func missingWeightsAreDroppedNotZeroed() {
        let day = cal.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        let byDay = DailyWeight.byDay([Reading(date: day, kg: nil)],
                                      date: \.date, weightKg: \.kg, calendar: cal)
        #expect(byDay.isEmpty)
    }

    /// End to end through the assembler: two readings on one day reach the
    /// engine as the lower of them.
    @Test func theAssemblerPassesTheLowestToTheEngine() {
        let day = cal.date(byAdding: .day, value: -2, to: .now)!
        let metrics = [
            BodyMetrics(date: cal.startOfDay(for: day).addingTimeInterval(7 * 3600), weightKg: 80.2),
            BodyMetrics(date: cal.startOfDay(for: day).addingTimeInterval(21 * 3600), weightKg: 81.6),
        ]
        let records = MetabolicRecordAssembler.dailyRecords(logs: [], metrics: metrics)
        #expect(records.count == 1)
        #expect(records.first?.weightKg == 80.2)
    }

    /// The smoothed trend is built from day values too, not from raw readings.
    ///
    /// A second weigh-in used to enter the EWMA as another point, and the
    /// time-aware decay floors the gap at a day — so stepping on the scale twice
    /// aged the trend by a day and pulled it toward the heavier reading.
    @Test @MainActor func theStoredTrendIgnoresHeavierSameDayReadings() throws {
        func trend(alsoWeighingInTheEvening: Bool) throws -> Double {
            let container = try ModelContainer(
                for: Schema(AppSchema.models),
                configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
            let context = ModelContext(container)
            for d in stride(from: 20, through: 0, by: -1) {
                let day = cal.date(byAdding: .day, value: -d, to: .now)!
                let morning = cal.startOfDay(for: day).addingTimeInterval(7 * 3600)
                context.insert(BodyMetrics(date: morning, weightKg: 80))
                if alsoWeighingInTheEvening {
                    context.insert(BodyMetrics(date: morning.addingTimeInterval(13 * 3600),
                                               weightKg: 81.5))
                }
            }
            AggregationService(context: context).fillWeightTrend()
            let rows = ((try? context.fetch(FetchDescriptor<BodyMetrics>())) ?? [])
                .sorted { $0.date < $1.date }
            return try #require(rows.last?.trendWeightKg)
        }
        let mornings = try trend(alsoWeighingInTheEvening: false)
        let both = try trend(alsoWeighingInTheEvening: true)
        #expect(abs(mornings - both) < 0.001,
                "an evening habit must not move the trend: \(mornings) against \(both)")
        #expect(abs(mornings - 80) < 0.001)
    }

    /// An evening re-weigh must not register as a gain the engine turns into
    /// calories. Flat mornings with a drifting evening habit used to do exactly
    /// that: at 7,700 kcal/kg, half a kilo of phantom gain is real money.
    @Test func anEveningReWeighHabitDoesNotCreateAPhantomTrend() {
        let engine = MetabolismEngine()
        let prior = MetabolismEngine.Prior(sex: .male, ageYears: 30, heightCm: 180,
                                           activity: .moderate)
        let start = Date(timeIntervalSince1970: 1_700_000_000)

        // Mornings dead flat at 80. From the third week the user starts also
        // weighing in the evening, where they read a kilo heavier.
        var records: [DailyRecord] = []
        for d in 0..<28 {
            let day = cal.date(byAdding: .day, value: d, to: start)!
            records.append(DailyRecord(date: day.addingTimeInterval(7 * 3600),
                                       intakeKcal: 2500, weightKg: 80))
            if d >= 14 {
                records.append(DailyRecord(date: day.addingTimeInterval(20 * 3600),
                                           intakeKcal: nil, weightKg: 81))
            }
        }
        let asOf = cal.date(byAdding: .day, value: 28, to: start)!
        let slope = engine.estimate(records: records, windowDays: 30,
                                    prior: prior, asOf: asOf).trendSlopeKgPerWeek
        #expect(abs(slope) < 0.01, "flat mornings must read as flat, got \(slope)")
    }
}
