import SwiftUI

/// Design tokens sampled from the reference design (#164d50).
/// Dark teal→black gradient, hairline-outlined cards, muted gold accent.
enum Theme {

    // MARK: Colour

    // Sampled from the Figma file via the REST API, not by eye: every value here
    // is the literal fill on the corresponding node.
    /// The app's one accent, everywhere: tab icons, gauges, charts, links.
    ///
    /// The mustard the Figma file strokes the home glyph with, not the limier
    /// `#C4D13C` it fills the recovery gauge with. The file uses both, a couple of
    /// hundred hue degrees apart, and having two near-identical yellows made the
    /// selected tab look like a different shade of wrong next to everything else.
    /// One wins, and it's the one on the icon you look at most.
    static let gold = Color(hex: 0xC3A920)
    static let backgroundTop = Color(hex: 0x0C2627) // frame gradient stop 0
    static let backgroundBottom = Color.black       // frame gradient stop 1
    static let surface = Color(hex: 0x0F1D20)       // every card fill
    static let tabBar = Color(hex: 0x0A181B)        // bottom-navigation
    static let homeWell = Color(hex: 0x162D33)      // the raised home circle

    static let textPrimary = Color.white
    static let textSecondary = Color(hex: 0x799195) // every muted label
    static let hairline = Color(hex: 0x1D3437)
    static let divider = Color(hex: 0x1D3437)
    /// The gauge track and the settings button share this wash.
    static let wash = Color.white.opacity(0.05)

    /// The app's backdrop. Fixed to the screen, so scrolling content moves over
    /// a still gradient rather than dragging it along.
    static var background: some View {
        LinearGradient(colors: [backgroundTop, backgroundBottom],
                       startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }

    // MARK: Type
    //
    // The design uses Canva Sans, which isn't licensed for redistribution and
    // isn't on iOS. SF Pro Rounded is the closest native match — same geometric
    // skeleton and soft terminals — and costs no bundle size.

    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    /// The Figma file sets Inter throughout. Inter isn't on iOS and isn't
    /// redistributable here, and SF Pro — not the rounded cut used elsewhere —
    /// is by far the closest native match: same grotesque skeleton and flat
    /// terminals. Used for anything laid out against that file.
    static func text(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    static let cardRadius: CGFloat = 28
    static let tabBarRadius: CGFloat = 36

    /// Card radius away from the dashboard.
    ///
    /// The 28pt bevel is sized for the home screen's full-width cards, one per
    /// row. Reused on the denser screens — where boxes are smaller and often
    /// stacked — that much rounding eats the corners and the content starts
    /// fighting the curve. Same shape and border, less of it.
    static let cardRadiusCompact: CGFloat = 18

    /// Radius for controls rather than containers: search fields, pickers, the
    /// small bordered boxes that sit inline with text.
    static let controlRadius: CGFloat = 14
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}

/// Filled card with a hairline border — the design's defining shape. Content
/// supplies its own padding via `padding`.
///
/// Both, not either: the Figma cards carry a solid `#0F1D20` *and* a 1pt
/// `#1D3437` stroke. The stroke is nearly invisible against the fill, but it's
/// what separates a card from the background where the gradient runs darkest.
///
/// `strokeBorder` rather than `stroke`, because the file sets the alignment to
/// inside — a centred stroke would sit half a point outside the corner radius and
/// read as a fractionally larger, softer card.
struct ThemeCard<Content: View>: View {
    var padding: CGFloat = 18
    /// Defaults to the dashboard's bevel. Denser screens pass
    /// `Theme.cardRadiusCompact`.
    var radius: CGFloat = Theme.cardRadius
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity)
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            )
    }
}

/// Label above a value, centred — the card layout used throughout the design.
struct StatBlock: View {
    let title: String
    let value: String
    var suffix: String?
    var caption: String?
    var valueSize: CGFloat = 34

    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(Theme.font(15))
                .foregroundStyle(Theme.textPrimary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(Theme.font(valueSize))
                    .foregroundStyle(Theme.textPrimary)
                if let suffix {
                    Text(suffix)
                        .font(Theme.font(17))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            if let caption {
                Text(caption)
                    .font(Theme.font(14))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

extension View {
    /// Drops a `List`/`Form` onto the gradient: clears the system grouped
    /// background, restyles rows as translucent surfaces, and leaves room for
    /// the floating tab bar.
    func themedList() -> some View {
        scrollContentBackground(.hidden)
            .background(Theme.background)
            .listRowBackground(Theme.surface.opacity(0.55))
            .tint(Theme.gold)
            .safeAreaPadding(.bottom, 96)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .font(Theme.font(16))
    }
}

/// Applies the gradient backdrop and hides the system list/scroll chrome.
struct ThemedScreen<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 14) {
                    content
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 120)   // clears the floating tab bar
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        // Was `.hidden`, which on iOS 26 leaves the bar as Liquid Glass floating
        // over the gradient. Opaque and themed, matching every other screen.
        .themedChrome()
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}
