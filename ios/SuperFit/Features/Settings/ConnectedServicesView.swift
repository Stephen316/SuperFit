import SwiftUI

struct ConnectedServicesView: View {
    @Environment(\.openURL) private var openURL
    @State private var backendURL = UserDefaults.standard.string(forKey: "garminBackendURL") ?? ""
    @State private var isLinked = false
    @State private var busy = false

    private let garmin = GarminProvider()

    var body: some View {
        Form {
            Section {
                if isLinked {
                    LabeledContent("Garmin") {
                        Label("Connected", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                    Button("Disconnect", role: .destructive) {
                        Task { await garmin.unlink(); await refresh() }
                    }
                } else {
                    Button("Connect Garmin") { link() }
                        .disabled(URL(string: backendURL) == nil || busy)
                }
            } header: {
                Text("Garmin")
            } footer: {
                Text(isLinked
                     ? "HRV and sleep stages come from Garmin, which Garmin Connect doesn't share with Apple Health. Everything else still syncs through Apple Health."
                     : "Garmin's HRV and detailed sleep don't reach Apple Health. Connecting fills those gaps for recovery scoring.")
            }

            Section {
                TextField("https://your-backend.example.com", text: $backendURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .onSubmit(saveBackend)
            } header: {
                Text("Backend")
            } footer: {
                Text("Garmin requires a server to hold API credentials and receive their data pushes. See docs/GARMIN.md.")
            }
        }
        .navigationTitle("Connected services")
        .navigationBarTitleDisplayMode(.inline)
        .keyboardDoneButton()
        .task { await refresh() }
        .onOpenURL { url in
            guard url.scheme == "superfit", url.host == "garmin",
                  let token = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                      .queryItems?.first(where: { $0.name == "token" })?.value
            else { return }
            Task { await garmin.completeLinking(sessionToken: token); await refresh() }
        }
    }

    private func saveBackend() {
        guard let url = URL(string: backendURL), url.scheme == "https" else { return }
        Task { await garmin.setBackend(url); await refresh() }
    }

    private func link() {
        saveBackend()
        busy = true
        Task {
            defer { busy = false }
            if let url = await garmin.authorizationURL() { openURL(url) }
        }
    }

    private func refresh() async {
        isLinked = await garmin.isLinked
    }
}
