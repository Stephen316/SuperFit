import Testing
import Foundation
@testable import SuperFit

/// The efficiency band pins its clinical boundary at 85% and bands the rounded
/// percentage, so the word on the gauge never disagrees with the number beside it.
struct SleepEfficiencyTests {

    @Test("Below 75% reads Poor")
    func poor() {
        #expect(SleepEfficiencyBand(roundedPercent: 60) == .poor)
        #expect(SleepEfficiencyBand(roundedPercent: 74) == .poor)
    }

    @Test("75–84% reads Fair, and 85% is the healthy threshold, not fragmented")
    func fairToGoodBoundary() {
        #expect(SleepEfficiencyBand(roundedPercent: 75) == .fair)
        #expect(SleepEfficiencyBand(roundedPercent: 84) == .fair)
        #expect(SleepEfficiencyBand(roundedPercent: 85) == .good) // boundary belongs to Good
    }

    @Test("85–89% reads Good, 90%+ Excellent")
    func goodToExcellent() {
        #expect(SleepEfficiencyBand(roundedPercent: 89) == .good)
        #expect(SleepEfficiencyBand(roundedPercent: 90) == .excellent)
        #expect(SleepEfficiencyBand(roundedPercent: 98) == .excellent)
    }
}
