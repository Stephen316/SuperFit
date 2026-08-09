import Testing
import Foundation
@testable import SuperFit

private let cal = Calendar(identifier: .gregorian)
private let day0 = cal.startOfDay(for: Date(timeIntervalSince1970: 1_750_000_000))

private func night(_ dayOffset: Int, asleep: Int, inBed: Int? = nil,
                   deep: Int = 0, rem: Int = 0, core: Int = 0,
                   bedHour: Int? = nil, bedMinute: Int = 0) -> SleepNight {
    let date = cal.date(byAdding: .day, value: dayOffset, to: day0)!
    let bedtime = bedHour.map {
        cal.date(bySettingHour: $0, minute: bedMinute, second: 0, of: date)!
    }
    return SleepNight(date: date, asleepMinutes: asleep, inBedMinutes: inBed ?? asleep,
                      deepMinutes: deep, remMinutes: rem, coreMinutes: core,
                      bedtime: bedtime, wakeTime: nil)
}

struct SleepAnalyticsTests {

    // MARK: Overall score

    @Test func completeExcellentNightScoresOneHundred() throws {
        let score = try #require(SleepAnalytics().overallScore(
            for: night(0, asleep: 480, inBed: 480, deep: 63, rem: 96, core: 321)))
        #expect(score.score == 100)
        #expect(score.band == .excellent)
        #expect(score.dataCompleteness == 1)
    }

    @Test func overallScoreCombinesDurationEfficiencyAndStages() throws {
        let score = try #require(SleepAnalytics().overallScore(
            for: night(0, asleep: 360, inBed: 400, deep: 47, rem: 72, core: 241)))
        // 50% × 75 duration + 20% × 90 efficiency + full REM/deep credit.
        #expect(score.score == 86)
        #expect(score.durationScore == 75)
        #expect(score.efficiencyScore == 90)
        #expect(score.band == .good)
    }

    @Test func phoneOnlySleepUsesDurationWithoutInventingMissingQuality() throws {
        let score = try #require(SleepAnalytics().overallScore(
            for: night(0, asleep: 360, inBed: 0)))
        #expect(score.score == 75)
        #expect(score.efficiencyScore == nil)
        #expect(score.remScore == nil)
        #expect(score.deepScore == nil)
        #expect(score.dataCompleteness == 0.5)
    }

    @Test func overallScoreNeedsActualSleep() {
        #expect(SleepAnalytics().overallScore(for: night(0, asleep: 0)) == nil)
    }

    @Test func overallBandsUseTheRoundedDisplayedScore() {
        #expect(OverallSleepBand(roundedScore: 59) == .poor)
        #expect(OverallSleepBand(roundedScore: 60) == .fair)
        #expect(OverallSleepBand(roundedScore: 75) == .good)
        #expect(OverallSleepBand(roundedScore: 90) == .excellent)
    }

    @Test func summaryAveragesAndDebt() {
        let nights = [night(0, asleep: 420), night(1, asleep: 480), night(2, asleep: 450)]
        let s = SleepAnalytics().summary(nights)!
        #expect(s.nights == 3)
        #expect(abs(s.averageAsleepMinutes - 450) < 0.001)
        // Debt counts only shortfalls: 60 + 0 + 30
        #expect(abs(s.debtMinutes - 90) < 0.001)
    }

    @Test func efficiencyUsesInBedTime() throws {
        let s = SleepAnalytics().summary([night(0, asleep: 450, inBed: 500)])!
        let efficiency = try #require(s.averageEfficiency)
        #expect(abs(efficiency - 0.9) < 0.001)
    }

    @Test func surplusNightsDoNotOffsetDebt() {
        // A 10-hour night must not cancel a 6-hour night: debt is one-directional.
        let nights = [night(0, asleep: 360), night(1, asleep: 600)]
        let s = SleepAnalytics().summary(nights)!
        #expect(abs(s.debtMinutes - 120) < 0.001)
    }

    /// Bedtimes either side of midnight are 20 minutes apart, not 23 hours.
    @Test func consistencyHandlesMidnightWrap() {
        let nights = [night(0, asleep: 450, bedHour: 23, bedMinute: 50),
                      night(1, asleep: 450, bedHour: 0, bedMinute: 10),
                      night(2, asleep: 450, bedHour: 0, bedMinute: 0)]
        let sd = SleepAnalytics().bedtimeConsistency(nights)!
        #expect(sd < 15)
    }

    @Test func consistencyNeedsThreeBedtimes() {
        let nights = [night(0, asleep: 450, bedHour: 23), night(1, asleep: 450, bedHour: 23)]
        #expect(SleepAnalytics().bedtimeConsistency(nights) == nil)
    }

    @Test func erraticBedtimesScoreHigh() {
        let nights = [night(0, asleep: 450, bedHour: 21),
                      night(1, asleep: 450, bedHour: 1),
                      night(2, asleep: 450, bedHour: 23),
                      night(3, asleep: 450, bedHour: 2)]
        let sd = SleepAnalytics().bedtimeConsistency(nights)!
        #expect(sd > 90)
    }

    @Test func impactComparesHRVAcrossThreshold() {
        var nights: [SleepNight] = []
        var hrv: [Date: Double] = [:]
        for i in 0..<10 {
            let long = i % 2 == 0
            let n = night(i, asleep: long ? 480 : 360)
            nights.append(n)
            hrv[cal.startOfDay(for: n.date)] = long ? 55 : 44
        }
        let impact = SleepAnalytics().impact(nights: nights, hrvByDay: hrv)!
        #expect(abs(impact.longNightHRV - 55) < 0.001)
        #expect(abs(impact.shortNightHRV - 44) < 0.001)
        #expect(abs(impact.hrvDeltaPercent - 25) < 0.001)
    }

    @Test func impactWithheldOnThinData() {
        let nights = (0..<6).map { night($0, asleep: $0 < 3 ? 480 : 360) }
        var hrv: [Date: Double] = [:]
        for n in nights { hrv[cal.startOfDay(for: n.date)] = 50 }
        #expect(SleepAnalytics().impact(nights: nights, hrvByDay: hrv) == nil)
    }

    @Test func rollingAverageTrailsSevenNights() {
        let nights = (0..<9).map { night($0, asleep: 420) }
        let avg = SleepAnalytics().rollingAverage(nights)
        #expect(avg.count == 3)
        #expect(abs(avg[0].minutes - 420) < 0.001)
    }

    @Test func emptyInputReturnsNoSummary() {
        #expect(SleepAnalytics().summary([]) == nil)
        #expect(SleepAnalytics().summary([night(0, asleep: 0)]) == nil)
    }
}
