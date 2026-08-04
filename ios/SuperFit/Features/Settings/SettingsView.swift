import SwiftUI
import SwiftData

/// Gear in the top-right of every tab. Conflicting controls live top-left.
struct SettingsToolbarModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: .topBarTrailing) { SettingsGear() }
            .withoutGlassBackground()
        }
    }
}

extension View {
    func settingsToolbar() -> some View { modifier(SettingsToolbarModifier()) }
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(UnitSystem.storageKey) private var unitsRaw = UnitSystem.metric.rawValue
    @AppStorage(AppearanceMode.storageKey) private var appearanceRaw = AppearanceMode.system.rawValue
    @AppStorage(FoodRegionSetting.storageKey) private var foodRegionRaw = FoodRegionSetting.automatic

    var body: some View {
        NavigationStack {
            List {
                Section("Account") {
                    NavigationLink {
                        AccountView()
                    } label: {
                        Label("Account and backup", systemImage: "person.crop.circle")
                    }
                }

                Section("Profile") {
                    NavigationLink {
                        ProfileView()
                    } label: {
                        Label("Goal, body details, activity", systemImage: "person.text.rectangle")
                    }
                }

                // Moved here when the dashboard's Trends button became the
                // streak flame. That button was the only route to this screen,
                // so dropping it would have made every chart in the app
                // unreachable without deleting a line of them.
                Section("Trends") {
                    NavigationLink {
                        HistoryView()
                    } label: {
                        Label("Charts and history", systemImage: "chart.xyaxis.line")
                    }
                }

                Section("Appearance") {
                    Picker("Appearance", selection: $appearanceRaw) {
                        ForEach(AppearanceMode.allCases, id: \.rawValue) { mode in
                            Text(mode.displayName).tag(mode.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                Section("Units") {
                    Picker("Measurement units", selection: $unitsRaw) {
                        ForEach(UnitSystem.allCases, id: \.rawValue) { u in
                            Text(u.displayName).tag(u.rawValue)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section {
                    Picker("Country", selection: $foodRegionRaw) {
                        Text(FoodRegionSetting.automaticLabel())
                            .tag(FoodRegionSetting.automatic)
                        ForEach(FoodRegion.all) { region in
                            Text(region.displayName).tag(region.code)
                        }
                    }
                } header: {
                    Text("Food database")
                } footer: {
                    Text("Ranks that country's products first in food search, then "
                         + "neighbouring countries, then everywhere else. Nothing is "
                         + "hidden — set this to where you buy your food, which isn't "
                         + "always where your phone is configured.")
                }

                Section("Data sources") {
                    NavigationLink {
                        ConnectedServicesView()
                    } label: {
                        Label("Connected services", systemImage: "link")
                    }
                }

                Section("Legal") {
                    Label("Terms of service", systemImage: "doc.text")
                        .foregroundStyle(.secondary)
                    Label("Privacy policy", systemImage: "hand.raised")
                        .foregroundStyle(.secondary)
                    Text("Your health data stays on your device and your private iCloud. It is never sold or shared.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                // The MIT licence requires its notice to travel with the work, so
                // this is an obligation rather than a courtesy.
                Section("Acknowledgements") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Muscle diagram")
                        Text("Anatomy adapted from react-muscle-highlighter, "
                             + "used under the MIT licence.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Food data")
                        Text("USDA FoodData Central, and Open Food Facts under the "
                             + "Open Database License.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .themedChrome()
            .navigationBarTitleDisplayMode(.inline)
            .themedList()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
                .withoutGlassBackground()
            }
        }
    }
}
