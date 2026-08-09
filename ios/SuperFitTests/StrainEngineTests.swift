import Testing
import Foundation
@testable import SuperFit

/// Strain must read as a personal, mid-range number on ordinary days and reach
/// 100 only on a maximal one — and, like every Health-backed figure in the app,
/// stay silent when it has nothing to measure rather than invent a zero.
///
/// Expected values are derived from `CardioLoadAnalyzer.trimp` in-test, so these
/// pin the normalisation (anchor, personal peak, clamping, coverage) rather than
/// a brittle constant that would drift if the TRIMP coefficients ever changed.
struct StrainEngineTests {
    let cal = Calendar(identifier: .gregorian)
    let restingHR = 50.0
    let age = 30.0
    var maxHR: Double { CardioLoadAnalyzer.estimatedMaxHeartRate(age: age) }
    var day: Date { cal.date(from: DateComponents(year: 2026, month: 6, day: 15))! }

    private func at(_ dayOffset: Int, hour: Int = 12) -> Date {
        let base = cal.date(byAdding: .day, value: dayOffset, to: cal.startOfDay(for: day))!
        return cal.date(byAdding: .hour, value: hour, to: base)!
    }
    private func hr(_ ratio: Double) -> Double { restingHR + ratio * (maxHR - restingHR) }
    private func rec(_ offset: Int, minutes: Double, ratio: Double, hour: Int = 12) -> CardioRecord {
        CardioRecord(date: at(offset, hour: hour), durationMinutes: minutes, avgHeartRate: hr(ratio))
    }
    private func trimp(_ r: CardioRecord) -> Double {
        CardioLoadAnalyzer.trimp(r, restingHR: restingHR, maxHR: maxHR, isFemale: false)!
    }
    private func eval(_ records: [CardioRecord]) -> StrainEngine.Result? {
        StrainEngine().evaluate(records: records, on: day, restingHR: restingHR,
                                age: age, isFemale: false, calendar: cal)
    }
    private func pct(_ raw: Double, over reference: Double) -> Double {
        (min(raw / reference, 1) * 100).rounded()
    }

    @Test("A hard hour is real strain but well below maximal — anchored, not pegged to itself")
    func hardHour() {
        let r = rec(0, minutes: 60, ratio: 0.85)
        let result = eval([r])
        #expect(result?.strain == pct(trimp(r), over: StrainEngine.referenceAnchorTrimp))
        #expect(result?.band == .moderate)
        #expect((result?.strain ?? 0) > 40 && (result?.strain ?? 0) < 67)
        #expect(result?.dataCompleteness == 1)
    }

    @Test("A rest day has no workout strain to measure, so it reports no data")
    func restDay() {
        #expect(eval([rec(-1, minutes: 60, ratio: 0.8)]) == nil)
    }

    @Test("Workouts without heart rate can't be scored")
    func noHeartRate() {
        let r = CardioRecord(date: at(0), durationMinutes: 60, avgHeartRate: nil)
        #expect(eval([r]) == nil)
    }

    @Test("A maximal day reaches 100 and reads all out")
    func allOut() {
        let result = eval([rec(0, minutes: 240, ratio: 0.9)])
        #expect(result?.strain == 100)
        #expect(result?.band == .allOut)
    }

    @Test("A light day is scaled by the anchor, not pegged to its own tiny peak")
    func lightDayAnchored() {
        let r = rec(0, minutes: 20, ratio: 0.5)
        let result = eval([r])
        // Without the anchor floor this would read 100 (today is its own peak).
        #expect(result?.strain == pct(trimp(r), over: StrainEngine.referenceAnchorTrimp))
        #expect(result?.band == .light)
        #expect((result?.strain ?? 100) < 34)
    }

    @Test("A high personal peak lowers today's percentage — the scale is yours")
    func personalPeak() {
        let peakDay = rec(-30, minutes: 240, ratio: 0.9)
        let today = rec(0, minutes: 60, ratio: 0.85)
        let result = eval([peakDay, today])
        #expect(result?.strain == pct(trimp(today), over: trimp(peakDay)))
        // Lower than the same session reads against the anchor for a lighter base.
        #expect((result?.strain ?? 100) < pct(trimp(today), over: StrainEngine.referenceAnchorTrimp))
    }

    @Test("Two sessions in a day sum, and strength counts — strain is total exertion")
    func sumsSessions() {
        let morning = rec(0, minutes: 40, ratio: 0.80, hour: 7)   // e.g. a lift
        let evening = rec(0, minutes: 30, ratio: 0.85, hour: 18)  // e.g. a run
        let result = eval([morning, evening])
        #expect(result?.strain == pct(trimp(morning) + trimp(evening),
                                      over: StrainEngine.referenceAnchorTrimp))
        #expect((result?.strain ?? 0) > pct(trimp(morning), over: StrainEngine.referenceAnchorTrimp))
    }

    @Test("Coverage falls when some of the day's workouts lack heart rate")
    func partialCoverage() {
        let measured = rec(0, minutes: 60, ratio: 0.85, hour: 7)
        let unmeasured = CardioRecord(date: at(0, hour: 18), durationMinutes: 45, avgHeartRate: nil)
        let result = eval([measured, unmeasured])
        #expect(result?.dataCompleteness == 0.5)
        #expect(result?.strain == pct(trimp(measured), over: StrainEngine.referenceAnchorTrimp))
    }
}
