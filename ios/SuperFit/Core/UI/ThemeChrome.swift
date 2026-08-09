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

    private static var barTint: UIColor { UIColor(Theme.tabBar) }
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
            .background(Theme.background)
            .toolbarBackground(Theme.tabBar, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
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
            .scrollContentBackground(.hidden)
            .background(Theme.backgroundTop)
            .listRowBackground(Theme.surface)
            .listRowSeparatorTint(Theme.hairline)
            .tint(Theme.gold)
            .safeAreaPadding(.bottom, bottomPadding)
            .toolbarBackground(Theme.tabBar, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
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
}

struct FeatureBackground: View {
    var body: some View {
        Theme.backgroundTop.ignoresSafeArea()
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

/// Flat replacement for `.searchable`, whose field is glass on iOS 26.
struct ThemeSearchField: View {
    let prompt: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15))
                .foregroundStyle(Theme.textSecondary)
            TextField(prompt, text: $text)
                .font(Theme.text(15))
                .foregroundStyle(Theme.textPrimary)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                .fill(Theme.wash)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        )
    }
}
