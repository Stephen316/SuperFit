import Testing
import SwiftUI
@testable import SuperFit

/// The scanner behind the body map. It only ever needed `M`, `L`, `C` and `Z`,
/// and it was quietly missing one of the four.
struct BodyDiagramPathTests {

    private func kinds(_ path: Path) -> [String] {
        var out: [String] = []
        path.forEach { element in
            switch element {
            case .move:          out.append("M")
            case .line:          out.append("L")
            case .curve:         out.append("C")
            case .quadCurve:     out.append("Q")
            case .closeSubpath:  out.append("Z")
            }
        }
        return out
    }

    private func lineCount(_ path: Path) -> Int {
        kinds(path).filter { $0 == "L" }.count
    }

    @Test func lineSegmentsSurviveParsing() {
        let triangle = BodyDiagram.path(from: "M 0 0 L 1 0 L 1 1 Z")
        #expect(kinds(triangle) == ["M", "L", "L", "Z"])
    }

    /// The failure mode was worse than a missing edge. `flush` cleared the
    /// coordinates without moving the current point, so a dropped `L` left the
    /// next curve starting from the wrong place and skewed the whole shape.
    @Test func aLineMovesTheCurrentPointForWhatFollows() {
        let withLine = BodyDiagram.path(from: "M 0 0 L 1 0 C 1 0 1 1 0 1 Z")
        #expect(kinds(withLine) == ["M", "L", "C", "Z"])
        // The curve is anchored at the line's endpoint, so the shape reaches
        // x = 1. Dropping the line left it collapsed against the y axis.
        #expect(withLine.boundingRect.maxX == 1)
    }

    @Test func unknownCommandsAreStillIgnored() {
        // `A` was never emitted by the generator; if one ever appears it should
        // be skipped rather than misread as coordinates.
        #expect(kinds(BodyDiagram.path(from: "M 0 0 A 5 5 0 0 1 1 1 Z")) == ["M", "Z"])
    }

    /// The regression itself: 122 line segments across the four figures, plus
    /// more in the silhouettes, were being discarded. If this ever reads zero
    /// again the diagram is silently drawing the wrong shapes.
    @Test func everyFigureKeepsItsLineSegments() {
        var total = 0
        for figure in [BodyArt.Figure.male, .female] {
            for side in [BodyDiagram.Side.front, .back] {
                total += BodyDiagram.regions(side, figure).reduce(0) { $0 + lineCount($1.path) }
                total += BodyDiagram.silhouette(side, figure).reduce(0) { $0 + lineCount($1) }
            }
        }
        #expect(total > 200, "expected the artwork's line segments to be parsed, got \(total)")
    }

    /// Every region has at least one group, which the renderer relies on when it
    /// falls back to `groups[0]`.
    @Test func everyRegionNamesAtLeastOneMuscle() {
        for figure in [BodyArt.Figure.male, .female] {
            for side in [BodyDiagram.Side.front, .back] {
                #expect(BodyDiagram.regions(side, figure).allSatisfy { !$0.groups.isEmpty })
            }
        }
    }
}
