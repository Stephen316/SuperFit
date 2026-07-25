import SwiftUI
import SwiftData

/// Gear in the top-right of every tab. Conflicting controls live top-left.
struct SettingsToolbarModifier: ViewModifier {
    @State private var showing = false

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showing = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showing) { SettingsView() }
    }
}

extension View {
    func settingsToolbar() -> some View { modifier(SettingsToolbarModifier()) }
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(UnitSystem.storageKey) private var unitsRaw = UnitSystem.metric.rawValue
    @AppStorage(AppearanceMode.storageKey) private var appearanceRaw = AppearanceMode.system.rawValue

    var body: some View {
        NavigationStack {
            List {
                Section("Account") {
                    Label("Create account", systemImage: "person.crop.circle.badge.plus")
                        .foregroundStyle(.secondary)
                    Text("Sync across devices and connect with friends. Coming soon.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("Profile") {
                    NavigationLink {
                        ProfileView()
                    } label: {
                        Label("Goal, body details, activity", systemImage: "person.text.rectangle")
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

                Section("Legal") {
                    Label("Terms of service", systemImage: "doc.text")
                        .foregroundStyle(.secondary)
                    Label("Privacy policy", systemImage: "hand.raised")
                        .foregroundStyle(.secondary)
                    Text("Your health data stays on your device and your private iCloud. It is never sold or shared.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
        }
    }
}
