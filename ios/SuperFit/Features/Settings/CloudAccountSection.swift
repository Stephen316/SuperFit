import SwiftUI
import SwiftData

/// Sign-in and cloud backup, for `AccountView`.
///
/// Kept out of `AccountView` because that file already carries the Apple
/// credential, the file export and the erase flow, and adding a third identity
/// with its own form pushed it past what the type checker would solve.
struct CloudAccountSection: View {
    @Environment(\.modelContext) private var context
    @Bindable var account: SupabaseAccount
    @Bindable var backup: SupabaseBackup
    /// Restoring can erase, so the decision goes back to `AccountView`, which
    /// already owns the merge-or-replace confirmation used by file restore.
    var onRestore: (DataArchive) -> Void

    @State private var email = ""
    @State private var password = ""
    @State private var mode = Mode.signIn

    private enum Mode: String, CaseIterable {
        case signIn = "Sign in"
        case signUp = "Create account"
    }

    var body: some View {
        switch account.state {
        case .unconfigured: unconfigured
        case .signedOut:    signedOut
        case .signedIn:     signedIn
        }
    }

    // MARK: - No backend

    /// A fork of this repo with no Supabase project must not be shown a sign-in
    /// form that cannot work.
    private var unconfigured: some View {
        Section {
            Label(SupabaseConfig.problem == nil ? "Not set up" : "Check configuration",
                  systemImage: "icloud.slash")
                .foregroundStyle(SupabaseConfig.problem == nil ? Theme.textSecondary : .orange)
            if let problem = SupabaseConfig.problem {
                Text(problem)
                    .font(Theme.text(13))
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Account")
        } footer: {
            Text("Add a Supabase URL and anon key to Secrets.xcconfig to enable accounts and cloud backup. Everything works without one — your data just stays on this device.")
        }
    }

    // MARK: - Signed out

    private var signedOut: some View {
        Section {
            Picker("", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            TextField("Email", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            SecureField("Password", text: $password)
                .textContentType(mode == .signUp ? .newPassword : .password)

            Button(mode.rawValue) {
                Task {
                    if mode == .signUp {
                        await account.signUp(email: email, password: password)
                    } else {
                        await account.signIn(email: email, password: password)
                    }
                    password = ""
                }
            }
            .disabled(!credentialsLookUsable || account.busy)

            if mode == .signIn {
                Button("Forgot password") {
                    Task { await account.sendPasswordReset(email: email) }
                }
                .disabled(email.isEmpty || account.busy)
            }

            Button("Continue with Google") {
                Task { await account.signIn(with: .google) }
            }
            .disabled(account.busy)

            if SupabaseConfig.appleSignInEnabled {
                Button("Continue with Apple") {
                    Task { await account.signIn(with: .apple) }
                }
                .disabled(account.busy)
            }

            if let error = account.lastError {
                Text(error)
                    .font(Theme.text(13))
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Account")
        } footer: {
            // Names only the providers actually on screen. With Apple gated off
            // the old wording promised a button that isn't there.
            Text("An account keeps a copy of your data off this device, so you can move to a new phone or recover after a reinstall. \(SupabaseConfig.appleSignInEnabled ? "Apple and Google open" : "Google opens") a browser to sign in — no password is ever handled by this app.")
        }
    }

    /// Deliberately not validating the address shape beyond this. The server is
    /// the authority on whether an email exists, and a client-side rule that
    /// disagrees just blocks people with unusual but valid addresses.
    private var credentialsLookUsable: Bool {
        email.contains("@") && password.count >= 6
    }

    // MARK: - Signed in

    private var signedIn: some View {
        Section {
            LabeledContent("Signed in") {
                Label(emailLabel, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }

            LabeledContent("Last backup") {
                if let remote = backup.remote {
                    Text(remote.updated_at, format: .relative(presentation: .named))
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    Text("Never").foregroundStyle(Theme.textSecondary)
                }
            }

            Button("Back up now") {
                Task { await backup.push(context: context) }
            }
            .disabled(isWorking)

            Button("Restore from backup") {
                Task { if let archive = await backup.fetchArchive() { onRestore(archive) } }
            }
            .disabled(isWorking || backup.remote == nil)

            Button("Sign out") { Task { await account.signOut() } }
                .disabled(isWorking)

            Button("Delete cloud backup", role: .destructive) {
                Task { await backup.deleteRemote() }
            }
            .disabled(isWorking || backup.remote == nil)

            if case let .failed(message) = backup.status {
                Text(message)
                    .font(Theme.text(13))
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Account")
        } footer: {
            Text("Backing up replaces the copy stored for your account. This is a snapshot, not live sync — if you use two devices, back up from the one you last used before restoring on the other.")
        }
    }

    private var emailLabel: String {
        if case let .signedIn(_, email) = account.state, let email { return email }
        return "Signed in"
    }

    private var isWorking: Bool {
        account.busy || backup.status == .working
    }
}
