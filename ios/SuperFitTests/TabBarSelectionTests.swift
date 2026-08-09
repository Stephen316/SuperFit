import CoreGraphics
import XCTest
@testable import SuperFit

final class TabBarSelectionTests: XCTestCase {
    func testNearestTabTracksFingerAcrossBar() {
        let width: CGFloat = 500

        XCTAssertEqual(AppTab.nearest(to: 50, in: width), .diet)
        XCTAssertEqual(AppTab.nearest(to: 150, in: width), .train)
        XCTAssertEqual(AppTab.nearest(to: 250, in: width), .home)
        XCTAssertEqual(AppTab.nearest(to: 350, in: width), .weight)
        XCTAssertEqual(AppTab.nearest(to: 450, in: width), .sleep)
    }

    func testNearestTabClampsFingerBeyondBarEdges() {
        XCTAssertEqual(AppTab.nearest(to: -20, in: 500), .diet)
        XCTAssertEqual(AppTab.nearest(to: 520, in: 500), .sleep)
    }

    func testNearestTabRejectsInvalidWidth() {
        XCTAssertNil(AppTab.nearest(to: 0, in: 0))
        XCTAssertNil(AppTab.nearest(to: 0, in: -1))
    }
}
