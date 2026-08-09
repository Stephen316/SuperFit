import SwiftUI

/// Keeps optional explanations out of dense settings layouts while leaving
/// them one tap away and fully labelled for VoiceOver.
struct SettingsInfoButton: View {
    let title: String
    let message: String
    @State private var showingInfo = false

    var body: some View {
        Button {
            showingInfo = true
        } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.gold)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("About \(title)")
        .alert(title, isPresented: $showingInfo) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message)
        }
    }
}

struct SettingsSectionHeader: View {
    let title: String
    let information: String

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
            SettingsInfoButton(title: title, message: information)
        }
    }
}
