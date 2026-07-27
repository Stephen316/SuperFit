import Foundation
import SwiftUI
#if canImport(AuthenticationServices)
import AuthenticationServices
#endif

/// Signed-in identity for the app.
///
/// **Sign in with Apple, deliberately.** An email-and-password account would
/// need a server holding password hashes, a reset flow, and breach exposure —
/// all to identify one person to their own device. Apple's flow gives a stable
/// opaque user id with no credential for this app to store, lose, or leak, and
/// it's required anyway if an app offers third-party sign-in.
///
/// **The account is not what saves the data.** SwiftData already syncs to the
/// user's private CloudKit database, so logs survive app updates, reinstalls and
/// new devices on the same Apple ID whether or not they ever sign in. Signing in
/// names the account, confirms which iCloud identity the data belongs to, and
/// gives the Friends feature something to attach to later. `AccountView` says
/// this plainly rather than implying an account is doing the persisting.
@MainActor
@Observable
final class AccountManager {

    enum State: Equatable {
        case signedOut
        case signedIn(userID: String, displayName: String?)
        /// Credential existed but Apple now reports it revoked or transferred —
        /// the user removed the app from their Apple ID, or changed accounts.
        case revoked
    }

    private static let userIDAccount = "account.appleUserID"
    private static let displayNameKey = "account.displayName"

    private(set) var state: State = .signedOut

    init() {
        restore()
    }

    var isSignedIn: Bool {
        if case .signedIn = state { return true }
        return false
    }

    private func restore() {
        guard let userID = Keychain.read(Self.userIDAccount) else {
            state = .signedOut
            return
        }
        state = .signedIn(userID: userID,
                          displayName: UserDefaults.standard.string(forKey: Self.displayNameKey))
    }

    /// Apple only sends the name on the very first authorisation, so it's stored
    /// then or never — asking again later returns nil, not the name again.
    func completeSignIn(userID: String, fullName: PersonNameComponents?) {
        Keychain.write(userID, account: Self.userIDAccount)
        if let fullName {
            let formatted = PersonNameComponentsFormatter.localizedString(from: fullName,
                                                                         style: .default)
            if !formatted.isEmpty {
                UserDefaults.standard.set(formatted, forKey: Self.displayNameKey)
            }
        }
        restore()
    }

    /// Clears the credential. **Local data is untouched** — signing out of a
    /// training log should not delete months of it, and the data belongs to the
    /// iCloud account regardless. Erasing is a separate, explicit action in
    /// `AccountView` so it can never happen by accident.
    func signOut() {
        Keychain.delete(Self.userIDAccount)
        UserDefaults.standard.removeObject(forKey: Self.displayNameKey)
        state = .signedOut
    }

    /// Asks Apple whether the stored credential is still valid. Runs at launch:
    /// a user can revoke access from iOS Settings at any time, and continuing to
    /// show them as signed in would be a lie.
    func refreshCredentialState() async {
        #if canImport(AuthenticationServices)
        guard case .signedIn(let userID, _) = state else { return }
        let provider = ASAuthorizationAppleIDProvider()
        let credentialState = try? await provider.credentialState(forUserID: userID)
        switch credentialState {
        case .authorized, .none:
            break                      // still good, or couldn't ask — assume good
        case .revoked, .transferred:
            Keychain.delete(Self.userIDAccount)
            state = .revoked
        case .notFound:
            signOut()
        @unknown default:
            break
        }
        #endif
    }
}
