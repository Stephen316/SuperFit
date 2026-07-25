import Foundation

/// Garmin Health API client — talks to *your* backend, never to Garmin directly.
///
/// Why a backend is mandatory:
/// 1. Garmin's OAuth requires a consumer secret. Anything shipped in an app
///    binary is extractable, so the secret must live server-side.
/// 2. The Health API is push-based: Garmin POSTs new data to a registered
///    webhook. A phone has no stable URL to receive those pings.
///
/// The backend stores per-user Garmin tokens, receives webhooks, and exposes the
/// two endpoints below. See docs/GARMIN.md for the contract and setup.
actor GarminProvider: RecoveryProvider {

    struct Config: Sendable {
        /// Your deployed backend, e.g. https://api.yourdomain.com
        var baseURL: URL
        /// Populated after the user links their account; stored in the Keychain.
        var sessionToken: String?
    }

    private let session: URLSession
    private var config: Config?

    init(session: URLSession = .shared) {
        self.session = session
        self.config = GarminConfigStore.load()
    }

    var isLinked: Bool {
        config?.sessionToken != nil
    }

    /// Step 1 of linking: the URL to open in a browser. The backend performs the
    /// OAuth handshake with Garmin and redirects back to `superfit://garmin`.
    func authorizationURL() -> URL? {
        guard let base = config?.baseURL else { return nil }
        return base.appendingPathComponent("garmin/authorize")
    }

    /// Step 2: the redirect carries a session token minted by the backend.
    func completeLinking(sessionToken: String) {
        guard var c = config else { return }
        c.sessionToken = sessionToken
        config = c
        GarminConfigStore.save(c)
    }

    func unlink() {
        guard var c = config else { return }
        c.sessionToken = nil
        config = c
        GarminConfigStore.save(c)
    }

    func setBackend(_ url: URL) {
        let c = Config(baseURL: url, sessionToken: config?.sessionToken)
        config = c
        GarminConfigStore.save(c)
    }

    /// GET {base}/garmin/recovery?start=…&end=… → [RecoveryDTO]
    /// The backend normalizes Garmin's payloads into this shape so the app never
    /// depends on their wire format.
    func recoveryMetrics(in range: DateInterval) async throws -> [RecoveryMetrics] {
        guard let config, let token = config.sessionToken else { return [] }
        var comps = URLComponents(
            url: config.baseURL.appendingPathComponent("garmin/recovery"),
            resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "start", value: ISO8601DateFormatter().string(from: range.start)),
            .init(name: "end", value: ISO8601DateFormatter().string(from: range.end)),
        ]
        guard let url = comps.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if http.statusCode == 401 {
            unlink()                       // token revoked server-side
            throw URLError(.userAuthenticationRequired)
        }
        guard (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
        guard data.count < 5_000_000 else { throw URLError(.dataLengthExceedsMaximum) }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([RecoveryDTO].self, from: data).map(\.metrics)
    }
}

/// Backend response shape — stable regardless of Garmin's own format.
private struct RecoveryDTO: Decodable {
    let date: String              // yyyy-MM-dd
    let hrvSDNN: Double?
    let restingHeartRate: Double?
    let bodyBattery: Int?
    let sleep: SleepDTO?

    struct SleepDTO: Decodable {
        let inBedMinutes: Int
        let asleepMinutes: Int
        let deepMinutes: Int
        let remMinutes: Int
        let lightMinutes: Int
        let bedtime: Date?
        let wakeTime: Date?
    }

    var metrics: RecoveryMetrics {
        let day = DateFormatter.garminDay.date(from: date) ?? Date()
        return RecoveryMetrics(
            day: day,
            hrvSDNN: hrvSDNN,
            restingHR: restingHeartRate,
            sleep: sleep.map {
                SleepSample(day: day,
                            inBedMinutes: $0.inBedMinutes,
                            asleepMinutes: $0.asleepMinutes,
                            deepMinutes: $0.deepMinutes,
                            remMinutes: $0.remMinutes,
                            coreMinutes: $0.lightMinutes,
                            bedtime: $0.bedtime,
                            wakeTime: $0.wakeTime)
            },
            bodyBattery: bodyBattery)
    }
}

private extension DateFormatter {
    static let garminDay: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f
    }()
}

/// Backend URL in UserDefaults (not secret); session token in the Keychain.
enum GarminConfigStore {
    private static let urlKey = "garminBackendURL"
    private static let account = "garmin.session"

    static func load() -> GarminProvider.Config? {
        guard let raw = UserDefaults.standard.string(forKey: urlKey),
              let url = URL(string: raw) else { return nil }
        return .init(baseURL: url, sessionToken: Keychain.read(account))
    }

    static func save(_ config: GarminProvider.Config) {
        UserDefaults.standard.set(config.baseURL.absoluteString, forKey: urlKey)
        if let token = config.sessionToken {
            Keychain.write(token, account: account)
        } else {
            Keychain.delete(account)
        }
    }
}

enum Keychain {
    static func write(_ value: String, account: String) {
        delete(account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func read(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ account: String) {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword,
                       kSecAttrAccount as String: account] as CFDictionary)
    }
}
