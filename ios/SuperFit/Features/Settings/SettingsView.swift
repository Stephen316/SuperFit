import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(UnitSystem.storageKey) private var unitsRaw = UnitSystem.metric.rawValue

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
