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
            // Seeded here rather than in SupplementsView: food-like supplements
            // are searchable from the food diary, so they must exist even if
            // that screen is never opened.
            SupplementCatalog.seedIfNeeded(context: context)
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

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeOut(duration: 0.18)) { selection = tab }
                } label: {
                    item(tab)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
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
        } else {
            VStack(spacing: 4) {
                Image(systemName: tab.icon)
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(tint)
                Text(tab.title)
                    .font(Theme.text(11, .medium))
                    .foregroundStyle(tint)
            }
            .frame(height: 72)
        }
    }
}
