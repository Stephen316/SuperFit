import SwiftUI

/// Design tokens sampled from the reference design (#164d50).
/// Dark teal→black gradient, hairline-outlined cards, muted gold accent.
enum Theme {

    // MARK: Colour

    static let gold = Color(hex: 0xBDA632)
    static let backgroundTop = Color(hex: 0x0C2526)
    static let backgroundBottom = Color.black
    static let surface = Color(hex: 0x0C2526)
    static let tabBar = Color(hex: 0x061414)

    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.55)
    static let hairline = Color.white.opacity(0.55)
    static let divider = Color.white.opacity(0.35)

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

    static let cardRadius: CGFloat = 28
    static let tabBarRadius: CGFloat = 36
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

/// Outlined card: no fill, hairline border, generous radius — the design's
/// defining shape. Content supplies its own padding via `padding`.
struct ThemeCard<Content: View>: View {
    var padding: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity)
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .stroke(Theme.hairline, lineWidth: 1)
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
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}
