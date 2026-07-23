import Testing
import Foundation
@testable import SuperFit

private let benchID = UUID()
private let squatID = UUID()

private let muscles: [UUID: ExerciseMuscles] = [
    benchID: .init(primary: .chest, secondary: [.triceps, .shoulders]),
    squatID: .init(primary: .quads, secondary: [.glutes, .core]),
]

private func lift(_ daysAgo: Int, _ id: UUID, _ kg: Double, _ reps: Int,
                  warmup: Bool = false) -> LiftRecord {
    LiftRecord(date: Date().addingTimeInterval(-Double(daysAgo) * 86_400),
               exerciseID: id, weightKg: kg, reps: reps, isWarmup: warmup)
}

@Suite struct VolumeAggregatorTests {

    private let week = DateInterval(start: Date().addingTimeInterval(-6 * 86_400),
                                    end: Date().addingTimeInterval(3600))

    @Test func primaryFullSecondaryHalfWarmupsExcluded() {
        let records = [
            lift(1, benchID, 100, 8), lift(1, benchID, 100, 8), lift(1, benchID, 100, 7),
            lift(2, squatID, 60, 5, warmup: true), lift(2, squatID, 80, 5, warmup: true),
            lift(2, squatID, 140, 5), lift(2, squatID, 140, 5), lift(2, squatID, 140, 4),
        ]
        let v = VolumeAggregator().weeklySets(records: records, muscles: muscles, week: week)
        #expect(v[.chest] == 3)
        #expect(v[.triceps] == 1.5)
        #expect(v[.shoulders] == 1.5)
        #expect(v[.quads] == 3)
        #expect(v[.glutes] == 1.5)
        #expect(v[.core] == 1.5)
        #expect(v[.back] == nil)
    }

    @Test func setsOutsideWeekExcluded() {
        let records = [lift(1, benchID, 100, 8), lift(10, benchID, 100, 8)]
        let v = VolumeAggregator().weeklySets(records: records, muscles: muscles, week: week)
        #expect(v[.chest] == 1)
    }

    @Test func tonnageAndFrequency() {
        let records = [
            lift(1, benchID, 100, 8), lift(1, benchID, 100, 8),
            lift(3, squatID, 140, 5),
            lift(3, squatID, 60, 5, warmup: true),
        ]
        let agg = VolumeAggregator()
        #expect(agg.tonnage(records: records, in: week) == 100 * 8 * 2 + 140 * 5)
        #expect(agg.frequency(records: records, in: week) == 2)
    }
}

@Suite struct ProgressionAnalyzerTests {

    private let analyzer = ProgressionAnalyzer()
    private let window = DateInterval(start: Date().addingTimeInterval(-60 * 86_400),
                                      end: Date())

    @Test func epleyE1RM() {
        #expect(abs(analyzer.e1RM(weightKg: 100, reps: 8) - 126.667) < 0.01)
        #expect(analyzer.e1RM(weightKg: 100, reps: 1) == 100)   // single = its own 1RM
        #expect(analyzer.e1RM(weightKg: 0, reps: 5) == 0)
    }

    @Test func highRepSetsCappedAtTwelve() {
        #expect(analyzer.e1RM(weightKg: 60, reps: 20) == analyzer.e1RM(weightKg: 60, reps: 12))
    }

    @Test func fivePercentStrengthGainDetected() {
        let records = [
            lift(50, benchID, 100, 5),   // earlier half best
            lift(45, benchID, 95, 5),
            lift(10, benchID, 105, 5),   // recent half best
            lift(5, benchID, 100, 5),
        ]
        let p = ProgressionAnalyzer().progressions(records: records, window: window)
        #expect(p.count == 1)
        #expect(abs(p[0].change - 0.05) < 0.001)
    }

    @Test func exerciseInOnlyOneHalfOmitted() {
        let records = [lift(5, benchID, 100, 5)]   // recent only
        #expect(ProgressionAnalyzer().progressions(records: records, window: window).isEmpty)
    }

    @Test func warmupsNeverCountTowardProgression() {
        let records = [
            lift(50, benchID, 100, 5),
            lift(5, benchID, 100, 5),
            lift(4, benchID, 180, 1, warmup: true),  // absurd warmup entry
        ]
        let p = ProgressionAnalyzer().progressions(records: records, window: window)
        #expect(abs(p[0].change) < 0.001)            // unchanged, warmup ignored
    }
}
