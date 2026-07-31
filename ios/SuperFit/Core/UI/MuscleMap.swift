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
/// All twenty groups are drawn separately. Two of them share a source path and
/// are separated by clipping it: the pectoral is cut into clavicular and sternal
/// heads, and the deltoid cap into its lateral head and the front or rear one —
/// which is why side delts show on both views.
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
            for region in BodyDiagram.regions(side) {
                let path = region.path.applying(t)
                let fill = colour(region.group)
                guard let clip = region.clip else {
                    context.fill(path, with: .color(fill))
                    continue
                }
                // Two muscles share this shape, so only the window belonging to
                // this one is painted. Layered so the clip can't leak into the
                // next region.
                context.drawLayer { layer in
                    layer.clip(to: Path(clip.applying(t)))
                    layer.fill(path, with: .color(fill))
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

    /// A parsed region: which muscle, the shape, and the window of it that
    /// belongs to that muscle when two share a path.
    struct Region {
        let group: MuscleGroup
        let path: Path
        let clip: CGRect?
    }

    static func regions(_ side: Side) -> [Region] {
        side == .front ? frontMuscles : backMuscles
    }

    static func silhouette(_ side: Side) -> [Path] {
        side == .front ? frontSilhouette : backSilhouette
    }

    /// Which groups are drawn on which view, so a caller can tell whether a
    /// muscle it wants to highlight is actually visible there.
    static func visibleGroups(_ side: Side) -> Set<MuscleGroup> {
        Set(regions(side).map(\.group))
    }

    // Parsed lazily and held: the data is ~150 paths of cubics, and reparsing it
    // on every redraw would be wasted work on a view that redraws whenever a set
    // is logged.
    private static let frontMuscles = parse(BodyArt.front)
    private static let backMuscles = parse(BodyArt.back)
    private static let frontSilhouette = BodyArt.frontSilhouette.map(path(from:))
    private static let backSilhouette = BodyArt.backSilhouette.map(path(from:))

    private static func parse(_ art: [BodyArt.Region]) -> [Region] {
        art.map { Region(group: $0.group, path: path(from: $0.d), clip: $0.clip) }
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
