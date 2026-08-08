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

        func settingBackend(_ newBaseURL: URL) -> Config {
            Config(baseURL: newBaseURL,
                   sessionToken: baseURL == newBaseURL ? sessionToken : nil)
        }
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
        GarminConfigStore.beginLinking()
        return base.appendingPathComponent("garmin/authorize")
    }

    /// Step 2: the redirect carries a session token minted by the backend.
    func completeLinking(sessionToken: String) {
        let token = sessionToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty,
              GarminConfigStore.consumePendingLink(),
              var c = GarminConfigStore.load() ?? config else { return }
        c.sessionToken = token
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
        let backendChanged = config?.baseURL != url
        let c = config?.settingBackend(url)
            ?? Config(baseURL: url, sessionToken: nil)
        config = c
        GarminConfigStore.save(c)
        if backendChanged { GarminConfigStore.cancelPendingLink() }
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

    /// GET {base}/garmin/workouts?start=…&end=… → [GarminWorkoutDTO]
    ///
    /// Enrichment, not a second source of truth. Garmin Connect already writes
    /// activities to Apple Health, so the same run usually arrives twice; the
    /// sync service matches on start time and fills in only what HealthKit has no
    /// field for — power, cadence, training effect. Workouts with no HealthKit
    /// counterpart (Connect's Health sync off) are imported whole.
    func workouts(in range: DateInterval) async throws -> [GarminWorkout] {
        guard let config, let token = config.sessionToken else { return [] }
        var comps = URLComponents(
            url: config.baseURL.appendingPathComponent("garmin/workouts"),
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
            unlink()
            throw URLError(.userAuthenticationRequired)
        }
        guard (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
        guard data.count < 5_000_000 else { throw URLError(.dataLengthExceedsMaximum) }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([GarminWorkoutDTO].self, from: data).map(\.workout)
    }
}

/// A Garmin activity, normalized by the backend.
struct GarminWorkout: Sendable, Equatable {
    let id: String
    let start: Date
    let end: Date
    let activity: WorkoutActivity
    var activeEnergyKcal: Double?
    var distanceMetres: Double?
    var avgHeartRate: Double?
    var maxHeartRate: Double?
    var elevationGainMetres: Double?
    var avgCadence: Double?
    var avgPowerWatts: Double?
    /// Garmin's aerobic/anaerobic training effect, already rendered to a phrase
    /// by the backend. Kept as text: the 0–5 scale is Garmin's own model and
    /// converting it into one of this app's numbers would imply a shared basis
    /// that doesn't exist.
    var trainingEffectSummary: String?
}

/// Backend response shape for activities.
struct GarminWorkoutDTO: Decodable {
    let id: String
    let startTime: Date
    let durationSeconds: Double
    /// Garmin's activity key, e.g. "running", "lap_swimming", "road_biking".
    let activityType: String
    let activeKilocalories: Double?
    let distanceMeters: Double?
    let averageHeartRate: Double?
    let maxHeartRate: Double?
    let elevationGainMeters: Double?
    let averageCadence: Double?
    let averagePowerWatts: Double?
    let aerobicTrainingEffect: Double?
    let anaerobicTrainingEffect: Double?

    var workout: GarminWorkout {
        GarminWorkout(
            id: id,
            start: startTime,
            end: startTime.addingTimeInterval(durationSeconds),
            activity: GarminWorkoutDTO.activity(for: activityType),
            activeEnergyKcal: activeKilocalories,
            distanceMetres: distanceMeters,
            avgHeartRate: averageHeartRate,
            maxHeartRate: maxHeartRate,
            elevationGainMetres: elevationGainMeters,
            avgCadence: averageCadence,
            avgPowerWatts: averagePowerWatts,
            trainingEffectSummary: Self.effectSummary(aerobic: aerobicTrainingEffect,
                                                      anaerobic: anaerobicTrainingEffect))
    }

    /// Garmin's activity keys → the app's taxonomy. Unknown keys land on `.other`
    /// so a new Garmin activity type imports rather than failing to decode.
    static func activity(for key: String) -> WorkoutActivity {
        switch key.lowercased() {
        case "running", "street_running": return .running
        case "trail_running": return .trailRunning
        case "treadmill_running", "indoor_running": return .treadmillRunning
        case "walking", "casual_walking", "speed_walking": return .walking
        case "hiking": return .hiking
        case "cycling", "road_biking", "gravel_cycling": return .cycling
        case "mountain_biking": return .mountainBiking
        case "indoor_cycling", "virtual_ride": return .indoorCycling
        case "lap_swimming": return .poolSwimming
        case "open_water_swimming": return .openWaterSwimming
        case "rowing": return .rowing
        case "indoor_rowing": return .indoorRowing
        case "stand_up_paddleboarding", "kayaking": return .paddling
        case "elliptical": return .elliptical
        case "stair_climbing", "indoor_climbing": return .stairClimbing
        case "hiit": return .hiit
        case "strength_training": return .strengthTraining
        case "yoga": return .yoga
        case "pilates": return .pilates
        case "tennis": return .tennis
        case "resort_skiing_snowboarding", "backcountry_skiing": return .skiing
        default: return .other
        }
    }

    static func effectSummary(aerobic: Double?, anaerobic: Double?) -> String? {
        switch (aerobic, anaerobic) {
        case let (a?, b?): return String(format: "Aerobic %.1f · anaerobic %.1f", a, b)
        case let (a?, nil): return String(format: "Aerobic %.1f", a)
        case let (nil, b?): return String(format: "Anaerobic %.1f", b)
        case (nil, nil): return nil
        }
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
    private static let pendingLinkKey = "garmin.pendingLinkStartedAt"
    private static let pendingLinkLock = NSLock()
    static let maxPendingLinkAge: TimeInterval = 10 * 60

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

    static func beginLinking(at now: Date = .now,
                             defaults: UserDefaults = .standard) {
        pendingLinkLock.lock()
        defer { pendingLinkLock.unlock() }
        defaults.set(now.timeIntervalSince1970, forKey: pendingLinkKey)
    }

    /// Removes the marker before returning so two handlers cannot accept the
    /// same callback, even when they receive the URL concurrently.
    static func consumePendingLink(at now: Date = .now,
                                   defaults: UserDefaults = .standard) -> Bool {
        pendingLinkLock.lock()
        defer { pendingLinkLock.unlock() }

        guard let stored = defaults.object(forKey: pendingLinkKey) as? NSNumber else {
            return false
        }
        defaults.removeObject(forKey: pendingLinkKey)
        let age = now.timeIntervalSince1970 - stored.doubleValue
        return age >= 0 && age <= maxPendingLinkAge
    }

    static func cancelPendingLink(defaults: UserDefaults = .standard) {
        pendingLinkLock.lock()
        defer { pendingLinkLock.unlock() }
        defaults.removeObject(forKey: pendingLinkKey)
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
