import Foundation
import Supabase
import SwiftUI

/// Where the backend lives, or nothing at all.
///
/// Both values are substituted from `Secrets.xcconfig` at build time. Leaving
/// them blank is a supported configuration, not a broken one: the app keeps
/// working exactly as it did before accounts existed, storing everything
/// locally. `isConfigured` is what the UI checks before offering to sign in, so
/// a fork of this repo without a Supabase project never shows a sign-in form
/// that cannot work.
enum SupabaseConfig {

    /// Built from a bare host, because xcconfig cannot hold a URL.
    ///
    /// `//` opens a comment in an xcconfig file, so `SUPABASE_URL =
    /// https://abc.supabase.co` reaches the build as `https:` and everything
    /// downstream fails for a reason that looks nothing like the cause. The
    /// setting therefore holds `abc.supabase.co` and the scheme is added here.
    ///
    /// A pasted full URL is still accepted — someone will paste one — by
    /// stripping the scheme back off before rebuilding it.
    static var url: URL? {
        guard let raw = value(for: "SupabaseURL") else { return nil }
        var host = raw
        for prefix in ["https://", "http://", "https:", "http:"] where host.hasPrefix(prefix) {
            host.removeFirst(prefix.count)
            break
        }
        // Host only — anything after the first slash is discarded.
        //
        // The dashboard shows several URLs and the Data API one carries a
        // `/rest/v1/` suffix. Keeping it would leave the SDK building
        // `/rest/v1/auth/v1/token`, which fails as a 404 that looks like a
        // server problem rather than a typo. Measured, not guessed: that is
        // exactly what was pasted the first time.
        host = host.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if let slash = host.firstIndex(of: "/") { host = String(host[host.startIndex..<slash]) }
        guard !host.isEmpty, host.contains("."), !host.contains(" ") else { return nil }
        return URL(string: "https://\(host)")
    }

    /// Checked for shape before it reaches the SDK.
    ///
    /// `SupabaseClient.init` asserts on a malformed key rather than throwing, so
    /// a truncated or mistyped paste takes the whole app down the moment the
    /// Settings screen builds — before any request is made, with a stack trace
    /// that points at SwiftUI rather than at the key. Measured, not guessed:
    /// that is exactly how this was found.
    ///
    /// Two shapes are valid. The classic anon key is a JWT (three dot-separated
    /// segments); the newer publishable keys are prefixed instead.
    static var anonKey: String? {
        guard let raw = value(for: "SupabaseAnonKey") else { return nil }
        if raw.hasPrefix("sb_publishable_"), raw.count > "sb_publishable_".count { return raw }
        let segments = raw.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count == 3, segments.allSatisfy({ !$0.isEmpty }) else { return nil }
        return raw
    }

    /// Set when something *was* supplied but could not be used, so the UI can
    /// say "check the key" instead of the much more misleading "not set up".
    static var problem: String? {
        let rawURL = value(for: "SupabaseURL")
        let rawKey = value(for: "SupabaseAnonKey")
        guard rawURL != nil || rawKey != nil else { return nil }
        if rawURL == nil { return "SUPABASE_URL is missing from Secrets.xcconfig." }
        if url == nil { return "SUPABASE_URL should be just the host, like abc.supabase.co (no https://)." }
        if rawKey == nil { return "SUPABASE_ANON_KEY is missing from Secrets.xcconfig." }
        if anonKey == nil { return "SUPABASE_ANON_KEY doesn't look complete — re-copy it from the dashboard." }
        return nil
    }

    static var isConfigured: Bool { url != nil && anonKey != nil }

    /// Whether to offer Apple as a sign-in provider.
    ///
    /// Off by default, because it cannot be made to work by editing this app.
    /// Configuring Apple as a Supabase provider needs a Services ID, a Team ID,
    /// a Key ID and a `.p8` private key from developer.apple.com — and all four
    /// require a paid Apple Developer Program membership, which this project
    /// does not have (see the entitlements file, where the `applesignin`
    /// capability is disabled for the same reason).
    ///
    /// Showing a button that returns an error from Apple's own servers is worse
    /// than not showing it, so the flag stays off until the membership exists.
    /// Set `SUPABASE_APPLE_SIGN_IN = YES` in Secrets.xcconfig to turn it on.
    static var appleSignInEnabled: Bool {
        guard let raw = value(for: "SupabaseAppleSignIn") else { return false }
        // Case-folded: an xcconfig is hand-edited, `Yes` and `TRUE` are what
        // people type, and matching only the exact spellings meant the flag
        // silently stayed off with no way to tell it apart from not setting it.
        return ["yes", "true", "1"].contains(raw.lowercased())
    }

    /// Unsubstituted placeholders come through literally when the xcconfig has
    /// no value, so they are treated as absent rather than as a key.
    private static func value(for key: String) -> String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("$(") else { return nil }
        return trimmed
    }
}

/// The signed-in Supabase user, and the ways to become one.
///
/// This sits alongside `AccountManager` rather than replacing it. That type
/// tracks the local Sign in with Apple credential and its reasoning still holds
/// for identifying a person to their own device. What it could never do is give
/// the data somewhere to live off the device — CloudKit is disabled here because
/// a free Apple team cannot sign the entitlement — which is the gap this fills.
///
/// Three ways in, because the answer to "how do I get my data onto a new phone"
/// should never be "you can't, you used the other button". Email and password is
/// the one that works everywhere with no Apple Developer membership and no
/// third-party account.
@MainActor
@Observable
final class SupabaseAccount {

    enum State: Equatable {
        case unconfigured
        case signedOut
        case signedIn(userID: UUID, email: String?)
    }

    private(set) var state: State = .unconfigured
    private(set) var busy = false
    private(set) var lastError: String?

    /// Nil when no backend is configured. Everything else on this type degrades
    /// to a no-op in that case rather than trapping.
    let client: SupabaseClient?

    /// Where OAuth hands control back. The scheme is already registered for the
    /// Garmin link, so this adds a host rather than a new scheme.
    static let redirectURL = URL(string: "superfit://auth-callback")!

    init() {
        if let url = SupabaseConfig.url, let key = SupabaseConfig.anonKey {
            client = SupabaseClient(supabaseURL: url, supabaseKey: key)
        } else {
            client = nil
        }
    }

    var isSignedIn: Bool {
        if case .signedIn = state { return true }
        return false
    }

    var userID: UUID? {
        if case let .signedIn(id, _) = state { return id }
        return nil
    }

    // MARK: - Session

    /// Restores a session from the keychain if the SDK has one cached.
    ///
    /// Deliberately tolerant: a network failure here must not lock someone out
    /// of an app whose data is on their device anyway, so a failed refresh
    /// reports signed out rather than surfacing an error.
    func restore() async {
        guard let client else { state = .unconfigured; return }
        do {
            let session = try await client.auth.session
            state = .signedIn(userID: session.user.id, email: session.user.email)
        } catch {
            state = .signedOut
        }
    }

    // MARK: - Email and password

    func signUp(email: String, password: String) async {
        await run { client in
            let response = try await client.auth.signUp(email: email, password: password)
            // With email confirmation enabled there is no session yet — the user
            // has to click the link first. Saying so beats a silent no-op.
            guard let session = response.session else {
                throw AuthMessage.confirmationRequired
            }
            return .signedIn(userID: session.user.id, email: session.user.email)
        }
    }

    func signIn(email: String, password: String) async {
        await run { client in
            let session = try await client.auth.signIn(email: email, password: password)
            return .signedIn(userID: session.user.id, email: session.user.email)
        }
    }

    func sendPasswordReset(email: String) async {
        await run { client in
            try await client.auth.resetPasswordForEmail(email, redirectTo: Self.redirectURL)
            // Still signed out; the mail does the rest.
            return .signedOut
        }
    }

    // MARK: - Third-party

    /// Google and Apple both go through the browser flow rather than a native
    /// SDK. For Google that avoids a second dependency and a client-id bundled
    /// into the app; for Apple it sidesteps the `applesignin` entitlement, which
    /// this project cannot sign on a free team — so the button works today
    /// instead of after a paid membership.
    func signIn(with provider: Provider) async {
        await run { client in
            let session = try await client.auth.signInWithOAuth(
                provider: provider,
                redirectTo: Self.redirectURL)
            return .signedIn(userID: session.user.id, email: session.user.email)
        }
    }

    // MARK: - Out

    /// Signs out, then re-derives state if the request failed.
    ///
    /// `run` only assigns state on success, which for every other call is right —
    /// a failed sign-in should leave you signed out. For sign-out it inverts the
    /// error: the request throws, `state` keeps saying `.signedIn`, and the UI
    /// offers to back up to an account the user has just left. Asking the SDK
    /// what the session actually is beats guessing in either direction.
    func signOut() async {
        await run { client in
            try await client.auth.signOut()
            return .signedOut
        }
        if lastError != nil { await restore() }
    }

    // MARK: - Plumbing

    private enum AuthMessage: LocalizedError {
        case confirmationRequired
        var errorDescription: String? {
            switch self {
            case .confirmationRequired:
                return "Check your email for a confirmation link, then sign in."
            }
        }
    }

    /// One place for the busy flag, the error surface and the unconfigured
    /// guard, so each entry point above is only its own request.
    private func run(_ body: @escaping (SupabaseClient) async throws -> State) async {
        guard let client else { state = .unconfigured; return }
        busy = true
        lastError = nil
        defer { busy = false }
        do {
            state = try await body(client)
        } catch {
            lastError = error.localizedDescription
        }
    }
}
