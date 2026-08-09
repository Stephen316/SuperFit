import SwiftUI
import UIKit

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    static let storageKey = "appAppearance"

    var id: Self { self }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// Design tokens sampled from the reference design (#164d50).
/// Deep teal backdrop, hairline-outlined cards, muted gold accent.
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
    /// A second, cooler accent used only for the strain gauge, so effort reads
    /// distinctly from the gold recovery ring beside it. Kept in the teal family
    /// of the background rather than an unrelated hue — one deliberate companion
    /// to the gold, not an ad-hoc colour.
    static let strain = Color(light: 0x287689, dark: 0x4FA3B5)
    /// The third gauge accent, for sleep — a calm indigo, the conventional sleep
    /// hue, distinct from the gold recovery and teal strain rings it sits beside.
    static let sleep = Color(light: 0x625AA7, dark: 0x8079C7)
    static let backgroundBase = Color(light: 0xFFFFFF, dark: 0x051011)
    static let surface = Color(light: 0xE4EEEE, dark: 0x0F1D20)
    static let tabBar = Color(light: 0xD8E5E5, dark: 0x0A181B)
    static let homeWell = Color(light: 0xC8DADB, dark: 0x162D33)

    static let textPrimary = Color(light: 0x122426, dark: 0xFFFFFF)
    static let textSecondary = Color(light: 0x4F676A, dark: 0x799195)
    static let hairline = Color(light: 0xBED0D1, dark: 0x1D3437)
    static let divider = hairline
    /// The gauge track and the settings button share this wash.
    static let wash = Color(light: 0xE7EEEE, dark: 0x1A2729)
    static let track = Color(light: 0xCADADB, dark: 0x232B2D)

    /// The app's adaptive solid backdrop.
    static var background: some View {
        backgroundBase.ignoresSafeArea()
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

    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
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

extension View {
    /// Drops a `List`/`Form` onto the backdrop: clears the system grouped
    /// background, restyles rows as translucent surfaces, and leaves room for
    /// the floating tab bar.
    func themedList(bottomPadding: CGFloat = 96) -> some View {
        scrollContentBackground(.hidden)
            .background(Theme.background)
            .listRowBackground(Theme.surface.opacity(0.55))
            .tint(Theme.gold)
            .safeAreaPadding(.bottom, bottomPadding)
            .toolbarBackground(.hidden, for: .navigationBar)
            .font(Theme.font(16))
    }
}
