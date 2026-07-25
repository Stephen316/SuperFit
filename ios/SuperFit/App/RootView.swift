import SwiftUI
import SwiftData

enum AppTab: String, CaseIterable {
    case diary, train, today, weight, sleep

    var title: String { rawValue.capitalized }
    var icon: String {
        switch self {
        case .today: return "square.grid.2x2"
        case .diary: return "fork.knife"
        case .train: return "dumbbell"
        case .weight: return "scalemass"
        case .sleep: return "moon.zzz"
        }
    }
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]
    @State private var tab = AppTab.today
    @AppStorage(AppearanceMode.storageKey) private var appearanceRaw = AppearanceMode.system.rawValue
    @State private var garmin = GarminProvider()

    var body: some View {
        TabView(selection: $tab) {
            DiaryView().tag(AppTab.diary).toolbar(.hidden, for: .tabBar)
            TrainingView().tag(AppTab.train).toolbar(.hidden, for: .tabBar)
            DashboardView().tag(AppTab.today).toolbar(.hidden, for: .tabBar)
            WeightView().tag(AppTab.weight).toolbar(.hidden, for: .tabBar)
            SleepView().tag(AppTab.sleep).toolbar(.hidden, for: .tabBar)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { tabBar }
        .preferredColorScheme((AppearanceMode(rawValue: appearanceRaw) ?? .system).colorScheme)
        .onOpenURL { url in handleDeepLink(url) }
        .task { ensureProfile() }
    }

    /// Compact custom bar: Today sits center and slightly larger.
    private var tabBar: some View {
        HStack {
            ForEach(AppTab.allCases, id: \.self) { t in
                Button {
                    tab = t
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: t.icon)
                            .font(.system(size: t == .today ? 24 : 18))
                        Text(t.title)
                            .font(.system(size: t == .today ? 11 : 9))
                    }
                    .fontWeight(t == .today ? .semibold : .regular)
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(tab == t ? Color.accentColor : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 6)
        .padding(.bottom, 2)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
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
