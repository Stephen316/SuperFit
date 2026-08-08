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
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]
    @State private var tab = AppTab.home
    @State private var garmin = GarminProvider()

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.background

            TabView(selection: $tab) {
                DiaryView().tag(AppTab.diet)
                TrainingView().tag(AppTab.train)
                DashboardView(tab: $tab).tag(AppTab.home)
                WeightView().tag(AppTab.weight)
                SleepView().tag(AppTab.sleep)
            }
            // Deliberately *not* `.page`. Its horizontal paging gesture wins over
            // every List row swipe in the app, so swipe-to-delete silently did
            // nothing anywhere — swiping a weigh-in changed tab instead. The
            // default style keeps each tab alive (so scroll positions and search
            // text survive switching) and leaves row swipes to the rows.
            .toolbar(.hidden, for: .tabBar)
            .ignoresSafeArea(.keyboard)

            TabBar(selection: $tab)
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
        .preferredColorScheme(.dark)
        .onOpenURL { handleDeepLink($0) }
        .task {
            ensureProfile()
            if UserDefaults.standard.bool(forKey: ReminderSettings.enabledKey) {
                await ReminderService.refresh()
            }
            // Seeded here rather than in SupplementsView: food-like supplements
            // are searchable from the food diary, so they must exist even if
            // that screen is never opened.
            SupplementCatalog.seedIfNeeded(context: context)
            // Bring the stored estimates back in line with the stored weights.
            //
            // The dashboard also aggregates, but only after awaiting a Health
            // sync — so a sync that stalls or is refused leaves a stale TDEE in
            // place indefinitely. This runs off nothing but the local store, so
            // a target left wrong by an earlier bug corrects itself on the next
            // launch instead of waiting to be edited a second time.
            AggregationService(context: context).refreshWeightDerived()
        }
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

    @State private var homeScale: CGFloat = 1

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
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                button(tab).frame(maxWidth: .infinity)
            }
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

    /// Home gets its own button style. `.plain` fades its label while held,
    /// which is unobtrusive on the small icon tabs but turns the well — a solid
    /// 83pt disc — translucent, so the bar looks like it flickers. Home keeps
    /// its opacity and pulses instead; the other four are left exactly as they
    /// were.
    @ViewBuilder
    private func button(_ tab: AppTab) -> some View {
        let select = {
            if tab == .home { pulseHome() }
            withAnimation(.easeOut(duration: 0.18)) { selection = tab }
        }
        if tab == .home {
            Button(action: select) { item(tab) }.buttonStyle(UndimmedButtonStyle())
        } else {
            Button(action: select) { item(tab) }.buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func item(_ tab: AppTab) -> some View {
        let active = selection == tab
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
