import SwiftUI
import UIKit

/// The home screen's language, applied to the rest of the app.
///
/// Every other screen was leaning on system chrome — navigation bars, search
/// fields, segmented controls — which on iOS 26 renders as Liquid Glass. Against
/// the flat, bordered, dark surfaces of the dashboard that reads as two apps
/// stitched together: the glass picks up a light tint and a specular edge that
/// nothing else on the screen has.
///
/// Two halves to the fix. `ThemeAppearance` reaches the UIKit views SwiftUI
/// wraps, because there is no SwiftUI API to opt a navigation bar out of glass.
/// The components below replace the controls worth rebuilding outright.
/// Every UIKit appearance proxy is main-actor isolated, so the whole type is.
/// Without this the 30-odd property writes below each warn under strict
/// concurrency, which is on for this project.
@MainActor
enum ThemeAppearance {

    /// Call once at launch, before any window is shown.
    static func apply() {
        navigationBars()
        searchFields()
        segmentedControls()
        tables()
    }

    private static var barTint: UIColor { UIColor(Theme.backgroundBase) }
    private static var washTint: UIColor { UIColor(Theme.surface) }
    private static var hairlineTint: UIColor { UIColor(Theme.hairline) }

    private static func navigationBars() {
        let appearance = UINavigationBarAppearance()
        // Opaque, not `configureWithDefaultBackground`: the default is what
        // resolves to Liquid Glass. An explicit opaque background is the
        // supported way to decline it.
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = barTint
        appearance.shadowColor = hairlineTint
        appearance.titleTextAttributes = [
            .foregroundColor: UIColor(Theme.textPrimary),
            .font: UIFont.systemFont(ofSize: 17, weight: .semibold)
        ]
        appearance.largeTitleTextAttributes = [
            .foregroundColor: UIColor(Theme.textPrimary),
            .font: UIFont.systemFont(ofSize: 30, weight: .bold)
        ]

        let bar = UINavigationBar.appearance()
        bar.standardAppearance = appearance
        bar.compactAppearance = appearance
        bar.scrollEdgeAppearance = appearance
        bar.compactScrollEdgeAppearance = appearance
        bar.tintColor = UIColor(Theme.gold)
    }

    private static func searchFields() {
        let field = UISearchTextField.appearance()
        field.backgroundColor = washTint
        field.textColor = UIColor(Theme.textPrimary)
        // The glass search bar sits on its own backdrop; flatten that too or the
        // field floats on a lighter panel.
        UISearchBar.appearance().backgroundImage = UIImage()
        UISearchBar.appearance().tintColor = UIColor(Theme.gold)
    }

    private static func segmentedControls() {
        let control = UISegmentedControl.appearance()
        control.selectedSegmentTintColor = UIColor(Theme.homeWell)
        control.backgroundColor = washTint
        control.setTitleTextAttributes(
            [.foregroundColor: UIColor(Theme.textSecondary),
             .font: UIFont.systemFont(ofSize: 13, weight: .medium)], for: .normal)
        control.setTitleTextAttributes(
            [.foregroundColor: UIColor(Theme.textPrimary),
             .font: UIFont.systemFont(ofSize: 13, weight: .semibold)], for: .selected)
    }

    private static func tables() {
        UITableView.appearance().backgroundColor = .clear
        UITableViewCell.appearance().backgroundColor = .clear
        UICollectionView.appearance().backgroundColor = .clear
    }
}

// MARK: - Screen background

private struct ThemedChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            // Lists and forms paint their own grouped background, which sits
            // over the gradient and greys it out.
            .scrollContentBackground(.hidden)
            .background(Theme.surface)
            .toolbarBackground(Theme.backgroundBase, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .foregroundStyle(Theme.textPrimary)
            // No `.buttonStyle` here, deliberately.
            //
            // This used to set `.plain` for the whole subtree to decline iOS 26's
            // glass capsule on bare buttons. It never did that job — as
            // `themedToolbarButton` below notes, toolbar content is hoisted into
            // its own hierarchy and a screen-level button style never reaches it
            // — and it silently broke every `swipeActions` in the app.
            //
            // A button style in scope stops SwiftUI decomposing a swipe action's
            // `Button` into a contextual action, so the tray comes back empty and
            // the row refuses to move: swipe-to-edit on a weigh-in, swipe-to-
            // delete on a food, a supplement, a meal ingredient. All silent, all
            // measured on device. Re-asserting a style inside `swipeActions`
            // does not rescue it; the style has to be absent from the List's
            // environment altogether.
            //
            // Buttons that need a flat label now say so themselves.
            .tint(Theme.gold)
    }
}

extension View {
    /// The dashboard's backdrop and bar treatment, for any screen that still
    /// uses a navigation bar or a List.
    func themedChrome() -> some View { modifier(ThemedChrome()) }
}

extension ToolbarContent {
    /// Drops the shared Liquid Glass background iOS 26 draws behind toolbar
    /// items. Independent of button style — `.plain` recolours the label but
    /// leaves the capsule, because the background belongs to the toolbar rather
    /// than to the button.
    ///
    /// Availability-gated rather than raising the deployment target: iOS 17 has
    /// no glass to decline.
    @ToolbarContentBuilder
    func withoutGlassBackground() -> some ToolbarContent {
        if #available(iOS 26.0, *) {
            self.sharedBackgroundVisibility(.hidden)
        } else {
            self
        }
    }
}

extension View {
    /// Strips the Liquid Glass capsule iOS 26 puts around toolbar buttons.
    ///
    /// Has to be applied to the button itself: toolbar content is hoisted into
    /// its own hierarchy, so a `.buttonStyle` set on the screen around the
    /// `.toolbar` modifier never reaches it.
    func themedToolbarButton() -> some View {
        buttonStyle(.plain).foregroundStyle(Theme.gold)
    }
}

// MARK: - Secondary screens

private struct FeatureListModifier: ViewModifier {
    let bottomPadding: CGFloat

    func body(content: Content) -> some View {
        content
            .listStyle(.plain)
            // A nonzero inter-section spacer makes a pinned header release
            // before its successor reaches the top, briefly exposing the light
            // content surface between two dark category bars.
            .listSectionSpacing(0)
            .scrollContentBackground(.hidden)
            .featureScrollEdgeTreatment()
            // The List canvas remains the deep home-screen teal so section
            // headers read as bars. Content rows opt into `Theme.surface` at
            // their declaration sites; SwiftUI does not inherit a row
            // background applied to the List itself.
            .background(Theme.backgroundBase)
            .listRowBackground(Theme.surface)
            .listRowSeparatorTint(Theme.hairline)
            .tint(Theme.gold)
            .foregroundStyle(Theme.textPrimary)
            .safeAreaPadding(.bottom, bottomPadding)
            .toolbarBackground(Theme.backgroundBase, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .font(Theme.text(16))
    }
}

private struct FeaturePanelModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            )
    }
}

extension View {
    func featureList(bottomPadding: CGFloat = 96) -> some View {
        modifier(FeatureListModifier(bottomPadding: bottomPadding))
    }

    func featurePanel() -> some View {
        modifier(FeaturePanelModifier())
    }

    /// iOS 26's automatic edge treatment fades and blurs the complete pinned
    /// section header. These opaque bars use List's native push handoff, so the
    /// system effect must not remove either the label or its teal container.
    @ViewBuilder
    fileprivate func featureScrollEdgeTreatment() -> some View {
        if #available(iOS 26.0, *) {
            scrollEdgeEffectHidden(true, for: .top)
        } else {
            self
        }
    }
}

struct FeatureBackground: View {
    var body: some View {
        Theme.surface.ignoresSafeArea()
    }
}

/// Full-width category separator for the four data-entry tabs. It uses the
/// dashboard canvas colour so headings remain visually distinct from the
/// lighter content rows without introducing another surface or accent.
///
/// **Always a plain row, never a `Section` header.** iOS 26's `List` cross-fades
/// one pinned header into the next, drawing both at partial opacity for the
/// length of the handoff — an arriving bar and the row behind it overlaid and
/// neither legible. That fade belongs to the pinning machinery and no public API
/// turns it off: `scrollEdgeEffectHidden` and `scrollEdgeEffectStyle` both act on
/// the scroll-edge effect, which is a different system, and neither changed it.
///
/// So the bars scroll like any other row, and `stickyCategoryHeaders()` draws the
/// pinned one in an overlay instead. See that modifier for the handoff.
struct FeatureCategoryBar: View {
    let title: String
    @Environment(CategoryBarTracker.self) private var tracker: CategoryBarTracker?

    /// Fixed, because the sticky overlay has to know a bar's height before the
    /// bar exists in order to push it off by exactly its own height.
    static let height: CGFloat = 48

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        FeatureCategoryLabel(title: title)
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onChange(of: proxy.frame(in: .global).minY, initial: true) { _, y in
                            tracker?.positions[title] = y
                            tracker?.seen.insert(title)
                        }
                        .onDisappear { tracker?.positions[title] = nil }
                }
            }
            .listRowInsets(.init())
            .listRowBackground(Theme.backgroundBase)
            .listRowSeparator(.hidden)
            .accessibilityAddTraits(.isHeader)
    }
}

/// The bar's appearance, with no list or measurement behaviour attached, so the
/// sticky overlay can draw an identical copy.
struct FeatureCategoryLabel: View {
    let title: String

    var body: some View {
        ZStack(alignment: .leading) {
            Theme.backgroundBase
            Text(title)
                .font(Theme.text(16, .semibold))
                .foregroundStyle(Theme.textPrimary)
                .textCase(nil)
                .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity, minHeight: FeatureCategoryBar.height, alignment: .leading)
    }
}

/// Where each category bar currently is, in screen coordinates.
///
/// A shared object rather than a `PreferenceKey`, because `List` hosts every row
/// in its own view hierarchy and preferences set inside a row never reach a
/// modifier on the List itself. Geometry callbacks cross that boundary; anchor
/// preferences silently do not, and the overlay simply never appears.
@Observable
final class CategoryBarTracker {
    /// Top of the list in screen coordinates, so bar positions can be made
    /// relative to it.
    var listTop: CGFloat = 0
    /// Title to its top edge in screen coordinates. Only bars the list has
    /// actually realised appear here — it recycles the rest.
    var positions: [String: CGFloat] = [:]
    /// Every bar the screen *can* show, in order, including ones scrolled out of
    /// the realised range. Needed to name the pinned bar once its own row has
    /// been recycled and can no longer report a position.
    var order: [String] = []
    /// Bars that have actually appeared. Several sections are conditional — the
    /// watch ones on Train, most of Sleep — so `order` lists headings that may
    /// never render. Falling back through `order` alone would pin the name of a
    /// section that is not on screen.
    var seen: Set<String> = []

    func offset(of title: String) -> CGFloat? {
        positions[title].map { $0 - listTop }
    }

    /// The bar that should be pinned, and how far the next one still has to
    /// travel before it starts pushing.
    func sticky(barHeight: CGFloat) -> (title: String, push: CGFloat)? {
        let placed = order.compactMap { title in offset(of: title).map { (title, $0) } }
        guard !placed.isEmpty else { return nil }

        let current: String
        if let passed = placed.last(where: { $0.1 <= 0 }) {
            current = passed.0
        } else if let ahead = placed.first(where: { $0.1 > 0 }),
                  let i = order.firstIndex(of: ahead.0),
                  let previous = order[..<i].last(where: { seen.contains($0) }) {
            // Its own row has been recycled, so fall back to the running order —
            // skipping conditional sections that never rendered.
            current = previous
        } else {
            return nil
        }

        let approaching = placed.first(where: { $0.1 > 0 })?.1 ?? .greatestFiniteMagnitude
        return (current, min(0, approaching - barHeight))
    }
}

/// Pins the current category bar under the navigation bar, and lets the next one
/// push it out of view.
///
/// The four states this reproduces, in scroll order:
///
/// 1. the bar sits still above its category while that category's rows scroll
/// 2. the next category's bar arrives directly beneath it
/// 3. the arriving bar pushes it up, and it is *clipped* by the top edge
/// 4. it is gone, and the arriving bar has taken its place
///
/// Step 3 is the whole point. `List`'s own pinning cross-fades there, drawing
/// both bars at partial opacity, which is illegible against the dark surface.
/// Here the outgoing bar is moved, not faded: `offset` slides it up by however
/// far the next bar has yet to travel, and `clipped()` removes what leaves the
/// top. Opacity is never touched.
private struct StickyCategoryHeaders: ViewModifier {
    let titles: [String]
    @State private var tracker = CategoryBarTracker()

    func body(content: Content) -> some View {
        content
            .environment(tracker)
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onChange(of: proxy.frame(in: .global).minY, initial: true) { _, y in
                            tracker.listTop = y
                        }
                }
            }
            .overlay(alignment: .top) {
                if let sticky = tracker.sticky(barHeight: FeatureCategoryBar.height) {
                    ZStack(alignment: .top) {
                        FeatureCategoryLabel(title: sticky.title)
                            .offset(y: sticky.push)
                    }
                    .frame(height: FeatureCategoryBar.height)
                    .clipped()
                    // Decoration only: taps must reach the rows underneath.
                    .allowsHitTesting(false)
                }
            }
            .onAppear { tracker.order = titles }
    }
}

extension View {
    /// Draws the current `FeatureCategoryBar` pinned at the top, pushed out by
    /// the next one. Apply to the `List`, alongside `featureList()`, passing the
    /// bar titles in the order they appear.
    func stickyCategoryHeaders(_ titles: [String]) -> some View {
        modifier(StickyCategoryHeaders(titles: titles))
    }
}

struct FeatureTabControl<Value: Hashable>: View {
    let options: [(value: Value, title: String)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                Button { selection = option.value } label: {
                    VStack(spacing: 0) {
                        Text(option.title)
                            .font(Theme.text(14, selection == option.value ? .semibold : .regular))
                            .foregroundStyle(selection == option.value
                                             ? Theme.textPrimary : Theme.textSecondary)
                            .frame(maxWidth: .infinity, minHeight: 42)
                        Rectangle()
                            .fill(selection == option.value ? Theme.gold : Color.clear)
                            .frame(height: 2)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == option.value ? .isSelected : [])
            }
        }
        .background(Theme.surface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.hairline).frame(height: 1)
        }
    }
}

// MARK: - Controls

/// The dashboard's day stepper, generalised: a hairline-bordered capsule of
/// segments divided by 1pt rules.
struct ThemeSegmentedControl<Value: Hashable>: View {
    let options: [(value: Value, title: String)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                if index > 0 {
                    Rectangle().fill(Theme.hairline).frame(width: 1, height: 16)
                }
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { selection = option.value }
                } label: {
                    Text(option.title)
                        .font(Theme.text(13, selection == option.value ? .semibold : .medium))
                        .foregroundStyle(selection == option.value
                                         ? Theme.textPrimary : Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .frame(minHeight: 44)
                        .background(selection == option.value ? Theme.homeWell : .clear)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == option.value ? .isSelected : [])
            }
        }
        .background(Capsule().fill(Theme.wash))
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
    }
}
