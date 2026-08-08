import SwiftUI

struct ConnectedServicesView: View {
    @Environment(\.openURL) private var openURL
    @State private var backendURL = UserDefaults.standard.string(forKey: "garminBackendURL") ?? ""
    @State private var isLinked = false
    @State private var busy = false
    @State private var usdaKey = USDAKeyStore.key ?? ""
    @State private var keyState: KeyState = {
        guard USDAKeyStore.key != nil else { return .unknown }
        return USDAKeyStore.isBundled ? .available : .valid
    }()
    @State private var checking = false
    @State private var showingServerSettings = false

    private let garmin = GarminProvider()
    private let usda = USDAClient()

    private enum KeyState { case unknown, available, valid, invalid }

    var body: some View {
        Form {
            Section {
                LabeledContent("USDA key") {
                    keyStatus
                }

                SecureField("Paste API key", text: $usdaKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit(saveKey)
                    .onChange(of: usdaKey) { _, value in
                        if value != USDAKeyStore.key { keyState = .unknown }
                    }

                HStack {
                    Button(checking ? "Checking…" : "Save and verify key") { saveKey() }
                        .disabled(usdaKey.trimmingCharacters(in: .whitespaces).isEmpty || checking)
                    Spacer()
                    if checking { ProgressView() }
                }

                Link("Get a free USDA key",
                     destination: URL(string: "https://fdc.nal.usda.gov/api-key-signup.html")!)
                    .font(Theme.font(13))
            } header: {
                Text("Food search")
            } footer: {
                Text("A free USDA key adds more generic and branded foods. Without one, search still uses Open Food Facts and foods you've logged before.")
            }

            Section {
                LabeledContent("Garmin Connect") {
                    Label(isLinked ? "Connected" : "Not connected",
                          systemImage: isLinked ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isLinked ? .green : Theme.textSecondary)
                }

                if isLinked {
                    Button("Disconnect Garmin", role: .destructive) {
                        Task { await garmin.unlink(); await refresh() }
                    }
                } else {
                    Button("Connect Garmin") { link() }
                        .disabled(validBackendURL == nil || busy)

                    if validBackendURL == nil {
                        Label("Server setup required", systemImage: "info.circle")
                            .font(Theme.font(13))
                            .foregroundStyle(Theme.textSecondary)
                    }

                    if busy {
                        ProgressView("Opening Garmin…")
                    }
                }

                if !isLinked {
                    DisclosureGroup("Server settings", isExpanded: $showingServerSettings) {
                        TextField("https://your-server.example.com", text: $backendURL)
                            .textContentType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .onSubmit(saveBackend)

                        if !backendURL.isEmpty && validBackendURL == nil {
                            Label("Enter a complete HTTPS address", systemImage: "exclamationmark.triangle.fill")
                                .font(Theme.font(13))
                                .foregroundStyle(.orange)
                        }

                        Button("Save server") { saveBackend() }
                            .disabled(validBackendURL == nil)
                    }
                }
            } header: {
                Text("Garmin")
            } footer: {
                Text(isLinked
                     ? "Garmin adds HRV and detailed sleep that Garmin Connect does not share with Apple Health."
                     : "Garmin can fill gaps in recovery data. It requires a separately hosted SuperFit server, configured under Server settings.")
            }
        }
        .navigationTitle("Connected services")
        .themedChrome()
        .navigationBarTitleDisplayMode(.inline)
        .themedList(bottomPadding: 24)
        .keyboardDoneButton()
        .task {
            await refresh()
            showingServerSettings = validBackendURL == nil
        }
        .onOpenURL { url in
            guard url.scheme == "superfit", url.host == "garmin",
                  let token = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                      .queryItems?.first(where: { $0.name == "token" })?.value
            else { return }
            Task { await garmin.completeLinking(sessionToken: token); await refresh() }
        }
    }

    @ViewBuilder
    private var keyStatus: some View {
        switch keyState {
        case .available:
            Label("Key available", systemImage: "key.fill")
                .foregroundStyle(Theme.gold)
        case .valid:
            Label("Verified", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .invalid:
            Label("Couldn't verify", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        case .unknown:
            Text("Not verified")
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var validBackendURL: URL? {
        let value = backendURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: value), url.scheme == "https", url.host != nil else {
            return nil
        }
        return url
    }

    private func saveKey() {
        let trimmed = usdaKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        checking = true
        Task {
            defer { checking = false }
            let ok = await usda.validate(key: trimmed)
            guard usdaKey.trimmingCharacters(in: .whitespacesAndNewlines) == trimmed else {
                return
            }
            keyState = ok ? .valid : .invalid
            if ok { USDAKeyStore.save(trimmed) }
        }
    }

    private func saveBackend() {
        guard let url = validBackendURL else { return }
        Task {
            await garmin.setBackend(url)
            await refresh()
        }
    }

    private func link() {
        guard let backend = validBackendURL else {
            showingServerSettings = true
            return
        }
        busy = true
        Task {
            defer { busy = false }
            // Save and read on the same actor task so authorization cannot race
            // the server update.
            await garmin.setBackend(backend)
            if let url = await garmin.authorizationURL() { openURL(url) }
        }
    }

    private func refresh() async {
        isLinked = await garmin.isLinked
    }
}
