import SwiftUI
import SwiftData

enum AppTab: String, CaseIterable {
    case diet, train, home, weight, sleep

    var title: String { rawValue.capitalized }

    /// Center tab is the anchor and carries no label, matching the design.
    var showsLabel: Bool { self != .home }

    var icon: String {
        switch self {
        case .diet: return "fork.knife"
        case .train: return "dumbbell"
        case .home: return "house"
        case .weight: return "scalemass"
        case .sleep: return "moon.stars"
        }
    }

    func moved(by offset: Int) -> AppTab? {
        guard let index = Self.allCases.firstIndex(of: self) else { return nil }
        let destination = index + offset
        guard Self.allCases.indices.contains(destination) else { return nil }
        return Self.allCases[destination]
    }

    /// The tab whose centre is nearest a horizontal point in the bar.
    /// Clamping keeps a finger just outside either edge attached to the first
    /// or last tab instead of cancelling an otherwise deliberate slide.
    static func nearest(to locationX: CGFloat, in width: CGFloat) -> AppTab? {
        guard width > 0, !allCases.isEmpty else { return nil }
        let segmentWidth = width / CGFloat(allCases.count)
        let index = min(max(Int(locationX / segmentWidth), 0), allCases.count - 1)
        return allCases[index]
    }
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]
    @AppStorage(AppAppearance.storageKey) private var appearanceRaw = AppAppearance.dark.rawValue
    @State private var tab = AppTab.home
    @State private var garmin = GarminProvider()
    @State private var tabDragOffset: CGFloat = 0

    private static let tabAnimation = Animation.easeOut(duration: 0.2)
    private static let dragTrackingRate: CGFloat = 0.82
    private static let edgeResistance: CGFloat = 0.18
    private static let completionFraction: CGFloat = 0.2

    var body: some View {
        ZStack {
            Theme.background

            GeometryReader { geometry in
                HStack(spacing: 0) {
                    DiaryView()
                        .frame(width: geometry.size.width)
                        .accessibilityHidden(tab != .diet)
                    TrainingView()
                        .frame(width: geometry.size.width)
                        .accessibilityHidden(tab != .train)
                    DashboardView(tab: $tab)
                        .frame(width: geometry.size.width)
                        .accessibilityHidden(tab != .home)
                    WeightView()
                        .frame(width: geometry.size.width)
                        .accessibilityHidden(tab != .weight)
                    SleepView()
                        .frame(width: geometry.size.width)
                        .accessibilityHidden(tab != .sleep)
                }
                .frame(width: geometry.size.width * CGFloat(AppTab.allCases.count),
                       alignment: .leading)
                .offset(x: -CGFloat(selectedTabIndex) * geometry.size.width + tabDragOffset)
                .animation(Self.tabAnimation, value: tab)
                // Normal gesture precedence is intentional: a child row's
                // swipeActions recognizer wins, so edit/delete never pages the
                // app at the same time. Areas without a child horizontal
                // gesture still provide the interactive tab swipe.
                .gesture(tabSwipeGesture(width: geometry.size.width))
            }
            .clipped()
        }
        // Keyboard presentation changes the bottom safe-area inset. If the bar
        // participates in that layout it rises above the keyboard and can retain
        // an intermediate position during a navigation transition. Ignore only
        // the keyboard region; the device/container safe area is still honoured.
        .ignoresSafeArea(.keyboard, edges: .bottom)
        // An overlay cannot contribute to the pager's size or inherit a child
        // screen's alignment, which gives the bar a second independent anchor.
        .overlay(alignment: .bottom) {
            TabBar(selection: $tab)
                .zIndex(1)
        }
        .overlay(alignment: .top) {
            if AppSchema.isEphemeral {
                Text("Storage unavailable — nothing logged this session will be saved.")
                    .font(Theme.font(13))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.85), in: Capsule())
                    .padding(.top, 4)
            }
        }
        .preferredColorScheme(appearance.colorScheme)
        .onOpenURL { handleDeepLink($0) }
        .task {
            ensureProfile()
            if UserDefaults.standard.bool(forKey: ReminderSettings.enabledKey) {
                await ReminderService.refresh(
                    state: ReminderStateLoader.load(context: context))
            }
            // Seeded here rather than in SupplementsView: food-like supplements
            // are searchable from the food diary, so they must exist even if
            // that screen is never opened.
            SupplementCatalog.seedIfNeeded(context: context)
        }
    }

    private var appearance: AppAppearance {
        AppAppearance(rawValue: appearanceRaw) ?? .dark
    }

    private var selectedTabIndex: Int {
        AppTab.allCases.firstIndex(of: tab) ?? 0
    }

    /// The page tracks most of the finger's travel, then settles to the next tab
    /// or returns home based on distance and predicted momentum. Keeping the
    /// gesture lower-priority and direction-locked leaves list scrolling and
    /// row edit/delete gestures in control. The leading 32 points remain
    /// reserved for NavigationStack's native back gesture.
    private func tabSwipeGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 24)
            .onChanged { value in
                let offset = interactiveOffset(for: value, width: width)
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { tabDragOffset = offset }
            }
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                let predicted = value.predictedEndTranslation.width
                let isHorizontal = value.startLocation.x >= 32 &&
                    abs(horizontal) > abs(vertical) * 1.2
                let crossedDistance = abs(horizontal) >= width * Self.completionFraction
                let hasMomentum = abs(horizontal) >= 32 && abs(predicted) >= width * 0.45
                let offset = horizontal < 0 ? 1 : -1

                if isHorizontal,
                   (crossedDistance || hasMomentum),
                   let destination = tab.moved(by: offset) {
                    withAnimation(Self.tabAnimation) {
                        tab = destination
                        tabDragOffset = 0
                    }
                } else {
                    withAnimation(Self.tabAnimation) { tabDragOffset = 0 }
                }
            }
    }

    private func interactiveOffset(for value: DragGesture.Value, width: CGFloat) -> CGFloat {
        let horizontal = value.translation.width
        let vertical = value.translation.height
        guard value.startLocation.x >= 32,
              abs(horizontal) > abs(vertical) * 1.2
        else { return 0 }

        let direction = horizontal < 0 ? 1 : -1
        let canChangeTab = tab.moved(by: direction) != nil
        let rate = canChangeTab ? Self.dragTrackingRate : Self.edgeResistance
        return min(max(horizontal * rate, -width), width)
    }

    private func ensureProfile() {
        guard profiles.isEmpty else { return }
        context.insert(UserProfile())
        try? context.save()
    }

    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "superfit", url.host == "garmin",
              let token = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                  .queryItems?.first(where: { $0.name == "token" })?.value
        else { return }
        Task { await garmin.completeLinking(sessionToken: token) }
    }
}

/// Presses the label through untouched — no dimming, no scaling. The press
/// feedback is supplied by whatever the label does itself.
private struct UndimmedButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label }
}

/// bottom-navigation from the Figma frame: 72pt tall, `#0A181B`, a 1pt `#1D3437`
/// hairline along the top, and the home tab raised out of it in an 83pt well.
///
/// Squared off rather than rounded, and the fill runs past the safe area to the
/// bottom of the screen. The frame floats the bar with 32pt beneath it, which on
/// a real device would show the background gradient through the home-indicator
/// strip; carrying the fill down was asked for and is what the bar does on
/// hardware.
private struct TabBar: View {
    @Binding var selection: AppTab

    /// SF Symbols are not drawn to a common height — the dumbbell is 16pt tall
    /// where the fork is 25pt. Centred in a VStack that left every label at a
    /// different height, Train worst at 4.7pt above its neighbours. A fixed box
    /// takes the icon out of the equation so the labels share a baseline.
    ///
    /// The exact value is calibrated, not arbitrary: it puts the label cap tops
    /// on 814.7pt, where scalemass and moon.stars already sat. Half of any
    /// change here lands on the labels, so a point added to the box moves them
    /// half a point down. Recalibrate if the 22pt symbol size changes.
    private static let iconBox: CGFloat = 26.667

    /// The bar lands on the bottom safe area, which on a Face ID phone leaves
    /// the home well floating a good 28pt clear of the screen edge — more air
    /// than the design has. This closes most of that gap, applied to the bar as
    /// a whole so the labels keep the alignment calibrated above.
    ///
    /// It puts the buttons' lower edge inside the home-swipe strip, where the
    /// system eats the first touch. Harmless as it stands, because the strip
    /// only covers blank space below the labels — but going much further would
    /// start taking bites out of the labels themselves.
    private static let dropBelowSafeArea: CGFloat = 16

    /// The home well answers a tap by pulsing: down to 92% and back, 500ms end
    /// to end, cubic in and out of the low point so it reads as one S rather
    /// than two straight moves with a corner between them.
    private static let pulseScale: CGFloat = 0.92
    private static let pulseDuration: Double = 0.5
    private static let selectionAnimation = Animation.easeOut(duration: 0.2)

    @State private var homeScale: CGFloat = 1
    /// GestureState resets on both completion and cancellation. A persistent
    /// State value can remain stuck when a competing row/system gesture wins
    /// before `onEnded`, leaving whichever tab was last previewed highlighted.
    @GestureState private var dragPreview: AppTab?

    /// Down and back, each leg an ease-in-out. That curve is already an S, and
    /// because it leaves and arrives at zero velocity the two legs meet at the
    /// low point without a corner — one smooth movement, not two.
    ///
    /// Driven off the completion handler rather than a delayed second call, so
    /// the return cannot start before the shrink has finished.
    private func pulseHome() {
        withAnimation(.easeInOut(duration: Self.pulseDuration / 2)) {
            homeScale = Self.pulseScale
        } completion: {
            withAnimation(.easeInOut(duration: Self.pulseDuration / 2)) {
                homeScale = 1
            }
        }
    }

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                ForEach(AppTab.allCases, id: \.self) { tab in
                    button(tab).frame(maxWidth: .infinity)
                }
            }
            .contentShape(Rectangle())
            .simultaneousGesture(barSwipeGesture(width: geometry.size.width))
        }
        .frame(height: 72)
        .background(alignment: .top) {
            Theme.tabBar
                .overlay(alignment: .top) {
                    Rectangle().fill(Theme.hairline).frame(height: 1)
                }
                .ignoresSafeArea(edges: .bottom)
        }
        // After the background has been told to reach the bottom edge, so the
        // fill still runs off the screen rather than leaving a strip behind it.
        .offset(y: Self.dropBelowSafeArea)
    }

    /// Sliding previews the tab nearest the finger, then commits that exact tab
    /// on release. The minimum distance keeps taps in the existing Buttons;
    /// unlike a tap, sliding onto Home does not trigger its press pulse.
    private func barSwipeGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .updating($dragPreview) { value, preview, _ in
                guard abs(value.translation.width) > abs(value.translation.height),
                      let nearest = AppTab.nearest(to: value.location.x, in: width)
                else {
                    preview = nil
                    return
                }
                preview = nearest
            }
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height),
                      let destination = AppTab.nearest(to: value.location.x, in: width)
                else { return }
                withAnimation(Self.selectionAnimation) { selection = destination }
            }
    }

    private func select(_ tab: AppTab) {
        if tab == .home { pulseHome() }
        // This is the original tap timing; sliding uses selectionAnimation
        // independently so adding drag tracking does not change button feel.
        withAnimation(.easeOut(duration: 0.18)) { selection = tab }
    }

    /// Home gets its own button style. `.plain` fades its label while held,
    /// which is unobtrusive on the small icon tabs but turns the well — a solid
    /// 83pt disc — translucent, so the bar looks like it flickers. Home keeps
    /// its opacity and pulses instead; the other four are left exactly as they
    /// were.
    @ViewBuilder
    private func button(_ tab: AppTab) -> some View {
        if tab == .home {
            Button { select(tab) } label: { item(tab) }
                .buttonStyle(UndimmedButtonStyle())
        } else {
            Button { select(tab) } label: { item(tab) }
                .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func item(_ tab: AppTab) -> some View {
        let active = (dragPreview ?? selection) == tab
        let tint = active ? Theme.gold : Theme.textSecondary

        if tab == .home {
            // The well is 83pt against a 72pt bar, so it stands proud of both
            // edges. Not a selection indicator: it stays put and only the tint
            // moves with the active tab.
            ZStack {
                Circle()
                    .fill(Theme.homeWell)
                    .frame(width: 83, height: 83)
                // Filled, not stroked: HouseGlyph is Figma's stroke *outline*.
                // The file colours it #C3A920, not the gauge's #C4D13C.
                HouseGlyph()
                    .fill(active ? Theme.gold : tint)
                    .frame(width: HouseGlyph.naturalSize.width,
                           height: HouseGlyph.naturalSize.height)
            }
            .frame(height: 72)
            // Well and glyph scale together. Shrinking the disc alone would
            // leave the house growing inside it, which reads as a mistake
            // rather than as a press.
            .scaleEffect(homeScale)
        } else {
            VStack(spacing: 4) {
                Image(systemName: tab.icon)
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(tint)
                    .frame(height: Self.iconBox)
                Text(tab.title)
                    .font(Theme.text(11, .medium))
                    .foregroundStyle(tint)
            }
            .frame(height: 72)
        }
    }
}
