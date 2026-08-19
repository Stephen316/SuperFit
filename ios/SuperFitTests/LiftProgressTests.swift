import Testing
import Foundation
@testable import SuperFit

/// The strength chart series must show the top working weight of each session,
/// ignore warm-ups and unweighted sets, honour the window, and surface the most
/// recently trained lifts first.
struct LiftProgressTests {
    let ex = UUID()
    let ex2 = UUID()
    let cal = Calendar(identifier: .gregorian)

    private func day(_ offset: Int) -> Date {
        cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: .now))!
    }
    private func rec(_ id: UUID, _ offset: Int, weight: Double,
                     reps: Int = 5, warmup: Bool = false) -> LiftRecord {
        LiftRecord(date: day(offset), exerciseID: id, weightKg: weight, reps: reps, isWarmup: warmup)
    }

    @Test("The heaviest working set of a session is that session's point")
    func maxPerSession() {
        let s = LiftProgress.series(records: [
            rec(ex, -1, weight: 80), rec(ex, -1, weight: 100), rec(ex, -1, weight: 90),
        ], since: day(-40))
        #expect(s.count == 1)
        #expect(s.first?.points.count == 1)
        #expect(s.first?.points.first?.maxWeightKg == 100)
    }

    @Test("Warm-ups and unweighted sets don't count toward the top weight")
    func excludesWarmupAndZero() {
        let s = LiftProgress.series(records: [
            rec(ex, -1, weight: 120, warmup: true),
            rec(ex, -1, weight: 0),
            rec(ex, -1, weight: 60),
        ], since: day(-40))
        #expect(s.first?.points.first?.maxWeightKg == 60)
    }

    @Test("Sessions outside the window are excluded")
    func windowFilters() {
        let s = LiftProgress.series(records: [
            rec(ex, -100, weight: 200), rec(ex, -5, weight: 80),
        ], since: day(-30))
        #expect(s.first?.points.map(\.maxWeightKg) == [80])
    }

    @Test("One point per session, ascending, series ordered by most recent")
    func orderingAndSessions() {
        let s = LiftProgress.series(records: [
            rec(ex, -10, weight: 70), rec(ex, -2, weight: 80), // ex last trained -2
            rec(ex2, -20, weight: 40),                          // ex2 last trained -20
        ], since: day(-60))
        #expect(s.count == 2)
        #expect(s.first?.exerciseID == ex)
        #expect(s.first?.points.map(\.maxWeightKg) == [70, 80])
        #expect(s.last?.exerciseID == ex2)
    }

    @Test("An exercise with only warm-ups or zeroes yields no series")
    func noQualifyingWork() {
        let s = LiftProgress.series(records: [
            rec(ex, -1, weight: 0), rec(ex, -1, weight: 50, warmup: true),
        ], since: day(-40))
        #expect(s.isEmpty)
    }

    // MARK: - Age-tiered downsampling

    private func pt(_ ageDays: Int, _ weight: Double) -> LiftProgressPoint {
        LiftProgressPoint(date: day(-ageDays), maxWeightKg: weight)
    }
    private func down(_ points: [LiftProgressPoint]) -> [LiftProgressPoint] {
        LiftProgress.downsample(points, asOf: day(0), calendar: cal)
    }

    @Test("Bucket keys tier by age: half-week, then weekly, then fortnightly")
    func bucketTiers() {
        #expect(LiftProgress.bucketKey(ageDays: 2) == LiftProgress.bucketKey(ageDays: 3))   // same half-week
        #expect(LiftProgress.bucketKey(ageDays: 3) != LiftProgress.bucketKey(ageDays: 5))   // next half-week
        #expect(LiftProgress.bucketKey(ageDays: 31) == LiftProgress.bucketKey(ageDays: 35)) // same week (months 2–3)
        #expect(LiftProgress.bucketKey(ageDays: 95) == LiftProgress.bucketKey(ageDays: 103))// same fortnight (4–6)
        #expect(LiftProgress.bucketKey(ageDays: 28) != LiftProgress.bucketKey(ageDays: 35)) // no straddling tier 1→2
        #expect(LiftProgress.bucketKey(ageDays: 88) != LiftProgress.bucketKey(ageDays: 95)) // no straddling tier 2→3
    }

    @Test("First month: two points a week, each the best of its half-week")
    func firstMonthTwiceWeekly() {
        // ages 1 & 3 share a half-week → best (100) survives; age 5 is the next half.
        let result = down([pt(1, 80), pt(3, 100), pt(5, 70)])
        #expect(result.count == 2)
        #expect(result.map(\.maxWeightKg).contains(100))
        #expect(!result.map(\.maxWeightKg).contains(80)) // beaten within its bucket
    }

    @Test("Months 2–3: one point a week, best only")
    func secondThirdMonthsWeekly() {
        let result = down([pt(32, 60), pt(34, 90), pt(36, 70)]) // all one week
        #expect(result.count == 1)
        #expect(result.first?.maxWeightKg == 90)
    }

    @Test("Months 4–6: one point a fortnight, best only, keeping its real date")
    func lastMonthsFortnightly() {
        let result = down([pt(95, 50), pt(100, 80), pt(102, 60)]) // one fortnight
        #expect(result.count == 1)
        #expect(result.first?.maxWeightKg == 80)
        #expect(result.first?.date == day(-100)) // the best session's actual date
    }

    // MARK: - All-time monthly sampling

    private func mdate(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d))!
    }
    private func mpt(_ y: Int, _ m: Int, _ d: Int, _ w: Double) -> LiftProgressPoint {
        LiftProgressPoint(date: mdate(y, m, d), maxWeightKg: w)
    }

    @Test("All-time: one point per month, the month's best, keeping its real date")
    func monthlyBest() {
        let result = LiftProgress.monthlyDownsample([
            mpt(2026, 3, 2, 80), mpt(2026, 3, 20, 110), mpt(2026, 3, 28, 90),
        ], calendar: cal)
        #expect(result.count == 1)
        #expect(result.first?.maxWeightKg == 110)
        #expect(result.first?.date == mdate(2026, 3, 20))
    }

    @Test("All-time keeps months distinct across a year boundary, ascending")
    func monthlyAcrossYears() {
        let result = LiftProgress.monthlyDownsample([
            mpt(2026, 1, 10, 105), mpt(2025, 12, 15, 100),
        ], calendar: cal)
        #expect(result.map(\.maxWeightKg) == [100, 105]) // Dec 2025 then Jan 2026
    }
}
