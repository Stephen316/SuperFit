import SwiftUI

/// Front and back body diagrams with every muscle group individually colourable.
///
/// Purely a renderer: it takes a colour per muscle and draws it. Deciding *which*
/// colour — how weekly volume maps to a shade — lives outside, so that mapping can
/// change without touching any geometry.
///
/// Muscles are drawn only where they're visible: chest and quads on the front,
/// lats and glutes on the back, forearms and calves on both. A muscle absent from
/// a view simply isn't drawn there rather than being faked onto it.
///
/// Two groups have no shape of their own, because the source anatomy doesn't
/// separate them: `upperChest` is drawn as part of `chest`, and `sideDelts` as
/// part of the front or rear deltoid. Volume still tracks all twenty separately —
/// callers that want the merged regions to reflect both should fold the values
/// before handing a colour over.
struct MuscleMap: View {
    /// Colour for each group. Anything unspecified falls back to `untrained`.
    var colour: (MuscleGroup) -> Color
    var untrained: Color = Theme.homeWell
    /// The body outline behind the muscles.
    var silhouette: Color = Theme.surface

    init(colours: [MuscleGroup: Color] = [:],
         untrained: Color = Theme.homeWell,
         silhouette: Color = Theme.surface) {
        self.colour = { colours[$0] ?? untrained }
        self.untrained = untrained
        self.silhouette = silhouette
    }

    init(untrained: Color = Theme.homeWell,
         silhouette: Color = Theme.surface,
         colour: @escaping (MuscleGroup) -> Color) {
        self.colour = colour
        self.untrained = untrained
        self.silhouette = silhouette
    }

    var body: some View {
        HStack(spacing: 10) {
            figure(.front)
            figure(.back)
        }
        .frame(maxWidth: .infinity)
    }

    private func figure(_ side: BodyDiagram.Side) -> some View {
        Canvas { context, size in
            // x was normalised by the source width and y by its height, so the
            // two axes need different scales — scaling both by the same factor
            // squashes the figure to half height.
            let width = min(size.width, size.height / BodyDiagram.aspect)
            let height = width * BodyDiagram.aspect
            let t = CGAffineTransform(translationX: (size.width - width) / 2,
                                      y: (size.height - height) / 2)
                .scaledBy(x: width, y: height)

            for path in BodyDiagram.silhouette(side) {
                context.fill(path.applying(t), with: .color(silhouette))
            }
            for (muscle, paths) in BodyDiagram.muscles(side) {
                let fill = colour(muscle)
                for path in paths {
                    context.fill(path.applying(t), with: .color(fill))
                }
            }
        }
        .aspectRatio(1 / BodyDiagram.aspect, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// Parses `BodyArt`'s path data into `Path`s, once.
enum BodyDiagram {
    enum Side { case front, back }

    /// The source figures are 724 wide by 1448 tall.
    static let aspect: CGFloat = 1448.0 / 724.0

    static func muscles(_ side: Side) -> [(MuscleGroup, [Path])] {
        side == .front ? frontMuscles : backMuscles
    }

    static func silhouette(_ side: Side) -> [Path] {
        side == .front ? frontSilhouette : backSilhouette
    }

    /// Which groups are drawn on which view, so a caller can tell whether a
    /// muscle it wants to highlight is actually visible there.
    static func visibleGroups(_ side: Side) -> Set<MuscleGroup> {
        Set(muscles(side).map(\.0))
    }

    // Parsed lazily and held: the data is ~150 paths of cubics, and reparsing it
    // on every redraw would be wasted work on a view that redraws whenever a set
    // is logged.
    private static let frontMuscles = parse(BodyArt.front)
    private static let backMuscles = parse(BodyArt.back)
    private static let frontSilhouette = BodyArt.frontSilhouette.map(path(from:))
    private static let backSilhouette = BodyArt.backSilhouette.map(path(from:))

    private static func parse(_ art: [(MuscleGroup, [String])]) -> [(MuscleGroup, [Path])] {
        art.map { ($0.0, $0.1.map(path(from:))) }
    }

    /// Absolute `M`, `C` and `Z` only — everything else was resolved to cubics
    /// when the data was generated, so this stays a scanner rather than a full
    /// SVG path implementation.
    static func path(from d: String) -> Path {
        var path = Path()
        var numbers: [CGFloat] = []
        numbers.reserveCapacity(6)
        var command: Character = "M"

        func flush() {
            switch command {
            case "M" where numbers.count >= 2:
                path.move(to: CGPoint(x: numbers[0], y: numbers[1]))
            case "C" where numbers.count >= 6:
                path.addCurve(to: CGPoint(x: numbers[4], y: numbers[5]),
                              control1: CGPoint(x: numbers[0], y: numbers[1]),
                              control2: CGPoint(x: numbers[2], y: numbers[3]))
            default:
                break
            }
            numbers.removeAll(keepingCapacity: true)
        }

        for field in d.split(separator: " ") {
            if let value = Double(field) {
                numbers.append(CGFloat(value))
                continue
            }
            flush()
            command = field.first ?? "M"
            if command == "Z" { path.closeSubpath() }
        }
        flush()
        return path
    }
}
