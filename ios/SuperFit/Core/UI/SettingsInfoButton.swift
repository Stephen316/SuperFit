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
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 18, height: 22)
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

extension View {
    /// A compact Form row for short status values. SwiftUI's default minimum
    /// leaves single-row settings cards looking mostly empty.
    func compactSettingsRow() -> some View {
        listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
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
