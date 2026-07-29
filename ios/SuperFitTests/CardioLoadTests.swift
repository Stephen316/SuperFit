import Testing
import Foundation
@testable import SuperFit

/// Cardio load must stay silent rather than report a ratio it can't support —
/// the same bar the cyclical baseline and recovery engine hold.
struct CardioLoadTests {

    private let cal = Calendar(identifier: .gregorian)
    private let today = Date(timeIntervalSince1970: 1_750_000_000)
    private let restingHR = 55.0
    private let age = 30.0

    private func day(_ offset: Int) -> Date {
        cal.date(byAdding: .day, value: offset, to: today)!
    }

    /// Four sessions a week for four weeks at a steady intensity.
    private func steady(minutes: Double = 45, hr: Double? = 145,
                        missingHRCount: Int = 0) -> [CardioRecord] {
        var out: [CardioRecord] = []
        var dropped = 0
        for offset in stride(from: -27, through: 0, by: 1) where [0, 2, 4, 6].contains((offset + 28) % 7) {
            let useHR: Double?
            if dropped < missingHRCount {
                useHR = nil
                dropped += 1
            } else {
                useHR = hr
            }
            out.append(CardioRecord(date: day(offset), durationMinutes: minutes,
                                    avgHeartRate: useHR))
        }
        return out
    }

    private func acwr(_ records: [CardioRecord]) -> CardioLoadAnalyzer.Result? {
        CardioLoadAnalyzer().acwr(records: records, on: today, restingHR: restingHR,
                                  age: age, isFemale: false, calendar: cal)
    }

    // MARK: TRIMP

    /// The exponential weighting is the point: a hard hour must outrank an easy
    /// one by more than the heart-rate difference alone.
    @Test func trimpRisesFasterThanIntensity() {
        let maxHR = CardioLoadAnalyzer.estimatedMaxHeartRate(age: age)
        func load(_ hr: Double) -> Double {
            CardioLoadAnalyzer.trimp(
                CardioRecord(date: today, durationMinutes: 45, avgHeartRate: hr),
                restingHR: restingHR, maxHR: maxHR, isFemale: false) ?? 0
        }
        let easy = load(110), hard = load(170)
        #expect(hard > easy * 3)
    }

    @Test func trimpIsNilWithoutHeartRate() {
        let maxHR = CardioLoadAnalyzer.estimatedMaxHeartRate(age: age)
        let record = CardioRecord(date: today, durationMinutes: 45, avgHeartRate: nil)
        #expect(CardioLoadAnalyzer.trimp(record, restingHR: restingHR,
                                         maxHR: maxHR, isFemale: false) == nil)
    }

    @Test func tanakaMaxHeartRateIsUsedNotTwoTwentyMinusAge() {
        #expect(abs(CardioLoadAnalyzer.estimatedMaxHeartRate(age: 30) - 187) < 0.5)
        #expect(abs(CardioLoadAnalyzer.estimatedMaxHeartRate(age: 50) - 173) < 0.5)
    }

    // MARK: ACWR behaviour

    @Test func steadyTrainingSitsAtOne() {
        let result = try? #require(acwr(steady()))
        if let result {
            #expect(abs(result.ratio - 1.0) < 0.15)
            #expect(result.band == .optimal)
        }
    }

    @Test func aSuddenBigWeekReadsAsASpike() {
        var records = steady()
        // Three extra hard sessions in the last week only.
        for offset in [-5, -3, -1] {
            records.append(CardioRecord(date: day(offset), durationMinutes: 90,
                                        avgHeartRate: 165))
        }
        let result = try? #require(acwr(records))
        if let result { #expect(result.ratio > 1.5) }
    }

    @Test func taperingReadsAsDetraining() {
        let records = steady().filter { $0.date < self.day(-7) }
        let result = try? #require(acwr(records))
        if let result {
            #expect(result.ratio < 0.8)
            #expect(result.band == .detraining)
        }
    }

    /// 1.3 is the top of the optimal band, matching the lifting ACWR.
    @Test func theOptimalBandIsClosedAtOnePointThree() {
        let onBoundary = CardioLoadAnalyzer.Result(ratio: 1.3, acuteLoad: 130,
                                                   chronicWeeklyLoad: 100)
        #expect(onBoundary.band == .optimal)
        let justAbove = CardioLoadAnalyzer.Result(ratio: 1.31, acuteLoad: 131,
                                                  chronicWeeklyLoad: 100)
        #expect(justAbove.band == .elevated)
    }

    // MARK: Refuses to answer without evidence

    @Test func noHistoryMeansNoRatio() {
        #expect(acwr([]) == nil)
    }

    /// Substituting duration for missing heart rate would mix two units in one
    /// series, so below the coverage bar it reports nothing at all.
    @Test func patchyHeartRateCoverageSuppressesTheRatio() {
        #expect(acwr(steady(missingHRCount: 6)) == nil)
    }

    @Test func aCoupleOfMissingReadingsStillAnswers() {
        #expect(acwr(steady(missingHRCount: 1)) != nil)
    }
}
