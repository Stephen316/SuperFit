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
/// The figure follows the profile's sex, because a body map that draws the wrong
/// body is a small but constant wrongness on a screen meant to describe *you*.
/// `.other` takes the male figure — something has to be drawn.
///
/// A region may name more than one muscle. Where the artwork draws two as one
/// shape — the middle and lower trapezius are a single band — the region is
/// coloured by whichever of them has seen the most work, not by their sum, so a
/// combined shape cannot read as well-trained merely for representing two
/// muscles.
struct MuscleMap: View {
    /// Which body to draw.
    var figure: BodyArt.Figure = .male

    /// Colour for each group. Anything unspecified falls back to `untrained`.
    var colour: (MuscleGroup) -> Color
    var untrained: Color = Theme.homeWell
    /// The body outline behind the muscles.
    var silhouette: Color = Theme.surface
    /// How much work a muscle has seen, used only to decide which of a shared
    /// region's muscles gives it its colour. Nil means take the first listed.
    var rank: ((MuscleGroup) -> Double)?

    init(colours: [MuscleGroup: Color] = [:],
         figure: BodyArt.Figure = .male,
         untrained: Color = Theme.homeWell,
         silhouette: Color = Theme.surface,
         rank: ((MuscleGroup) -> Double)? = nil) {
        self.figure = figure
        self.rank = rank
        self.colour = { colours[$0] ?? untrained }
        self.untrained = untrained
        self.silhouette = silhouette
    }

    init(figure: BodyArt.Figure = .male,
         untrained: Color = Theme.homeWell,
         silhouette: Color = Theme.surface,
         rank: ((MuscleGroup) -> Double)? = nil,
         colour: @escaping (MuscleGroup) -> Color) {
        self.figure = figure
        self.rank = rank
        self.colour = colour
        self.untrained = untrained
        self.silhouette = silhouette
    }

    var body: some View {
        // Tight: each figure's box is its own arm span, so the gap between them
        // is the only slack in the row.
        HStack(spacing: 4) {
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
            let ratio = BodyDiagram.aspect(figure)
            let width = min(size.width, size.height / ratio)
            let height = width * ratio
            let t = CGAffineTransform(translationX: (size.width - width) / 2,
                                      y: (size.height - height) / 2)
                .scaledBy(x: width, y: height)

            for path in BodyDiagram.silhouette(side, figure) {
                context.fill(path.applying(t), with: .color(silhouette))
            }
            for region in BodyDiagram.regions(side, figure) {
                let path = region.path.applying(t)
                // Highest, not summed: a shared shape must not read as better
                // trained just because it stands for two muscles. Colours can't
                // be ordered, so the caller supplies the ranking when it has
                // the volume to hand; otherwise the first-listed muscle wins.
                let group = region.groups.max { a, b in
                    (rank?(a) ?? 0) < (rank?(b) ?? 0)
                } ?? region.groups[0]
                let fill = colour(group)
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
        .aspectRatio(1 / BodyDiagram.aspect(figure), contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// Parses `BodyArt`'s path data into `Path`s, once.
enum BodyDiagram {
    enum Side { case front, back }

    /// The source figures are 724 wide by 1448 tall.
    /// Measured from each figure's own silhouette rather than assumed. The old
    /// constant belonged to different artwork, and applying it here letterboxed
    /// the figures inside their box instead of letting the arm span fill it.
    static func aspect(_ figure: BodyArt.Figure) -> CGFloat { BodyArt.aspect(figure) }

    /// A parsed region: which muscle, the shape, and the window of it that
    /// belongs to that muscle when two share a path.
    struct Region {
        let groups: [MuscleGroup]
        let path: Path
        let clip: CGRect?
    }

    static func regions(_ side: Side, _ figure: BodyArt.Figure) -> [Region] {
        switch (side, figure) {
        case (.front, .male):   return maleFront
        case (.back,  .male):   return maleBack
        case (.front, .female): return femaleFront
        case (.back,  .female): return femaleBack
        }
    }

    static func silhouette(_ side: Side, _ figure: BodyArt.Figure) -> [Path] {
        switch (side, figure) {
        case (.front, .male):   return maleFrontSil
        case (.back,  .male):   return maleBackSil
        case (.front, .female): return femaleFrontSil
        case (.back,  .female): return femaleBackSil
        }
    }

    /// Which groups are drawn on which view, so a caller can tell whether a
    /// muscle it wants to highlight is actually visible there.
    static func visibleGroups(_ side: Side, _ figure: BodyArt.Figure) -> Set<MuscleGroup> {
        Set(regions(side, figure).flatMap(\.groups))
    }

    // Parsed lazily and held: the data is ~150 paths of cubics, and reparsing it
    // on every redraw would be wasted work on a view that redraws whenever a set
    // is logged.
    private static let maleFront = parse(BodyArt.maleFront)
    private static let maleBack = parse(BodyArt.maleBack)
    private static let femaleFront = parse(BodyArt.femaleFront)
    private static let femaleBack = parse(BodyArt.femaleBack)
    private static let maleFrontSil = BodyArt.maleFrontSilhouette.map(path(from:))
    private static let maleBackSil = BodyArt.maleBackSilhouette.map(path(from:))
    private static let femaleFrontSil = BodyArt.femaleFrontSilhouette.map(path(from:))
    private static let femaleBackSil = BodyArt.femaleBackSilhouette.map(path(from:))

    private static func parse(_ art: [BodyArt.Region]) -> [Region] {
        art.map { Region(groups: $0.groups, path: path(from: $0.d), clip: $0.clip) }
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
