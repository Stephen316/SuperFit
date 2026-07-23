import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]

    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Today", systemImage: "square.grid.2x2") }
            DiaryView()
                .tabItem { Label("Diary", systemImage: "fork.knife") }
            TrainingView()
                .tabItem { Label("Train", systemImage: "dumbbell") }
            WeightView()
                .tabItem { Label("Weight", systemImage: "scalemass") }
            ProfileView()
                .tabItem { Label("Profile", systemImage: "person") }
        }
        .task { ensureProfile() }
    }

    private func ensureProfile() {
        guard profiles.isEmpty else { return }
        context.insert(UserProfile())
        try? context.save()
    }
}
