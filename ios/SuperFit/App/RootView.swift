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
                DashboardView().tag(AppTab.home)
                WeightView().tag(AppTab.weight)
                SleepView().tag(AppTab.sleep)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
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

/// Five tabs on a dark rounded bar. The centre well is a fixed part of the bar,
/// not a selection indicator — it stays put while the gold moves to whichever
/// tab is active.
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
        .padding(.horizontal, 8)
        .padding(.bottom, 6)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: Theme.tabBarRadius,
                                   topTrailingRadius: Theme.tabBarRadius,
                                   style: .continuous)
                .fill(Theme.tabBar)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    @ViewBuilder
    private func item(_ tab: AppTab) -> some View {
        let active = selection == tab
        let tint = active ? Theme.gold : Theme.textPrimary

        if tab == .home {
            ZStack {
                Circle()
                    .fill(Theme.surface)
                    .frame(width: 74, height: 74)
                Image(systemName: tab.icon)
                    .font(.system(size: 32, weight: .regular))
                    .foregroundStyle(tint)
            }
            .frame(height: 62)
            .offset(y: -12)
        } else {
            VStack(spacing: 5) {
                Image(systemName: tab.icon)
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(tint)
                Text(tab.title)
                    .font(Theme.font(13))
                    .foregroundStyle(tint)
            }
            .frame(height: 62)
        }
    }
}
