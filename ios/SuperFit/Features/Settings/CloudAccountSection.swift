import SwiftUI
import SwiftData

/// Sign-in and cloud backup, for `AccountView`.
///
/// Kept out of `AccountView` so authentication and remote-backup states stay
/// separate from file export, restore and on-device data controls.
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
    @State private var confirmingBackup = false
    @State private var confirmingDeleteBackup = false

    private enum Mode: String, CaseIterable {
        case signIn = "Sign in"
        case signUp = "Create account"
    }

    var body: some View {
        Group {
            switch account.state {
            case .unconfigured: unconfigured
            case .signedOut:    signedOut
            case .signedIn:     signedIn
            }
        }
        .task(id: account.userID) {
            backup.resetForAccountChange()
            guard account.isSignedIn else { return }
            await backup.refreshSummary()
        }
        .alert("Back up this device?", isPresented: $confirmingBackup) {
            Button("Back up now", role: .destructive) {
                Task { await backup.push(context: context) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This uploads a new snapshot and replaces any backup already stored for this account. Make sure this device has the data you want to keep.")
        }
        .alert("Delete cloud backup?", isPresented: $confirmingDeleteBackup) {
            Button("Delete cloud backup", role: .destructive) {
                Task { await backup.deleteRemote() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes only the backup stored for this account. Data on this device and the account itself are kept.")
        }
    }

    // MARK: - No backend

    /// A fork of this repo with no Supabase project must not be shown a sign-in
    /// form that cannot work.
    private var unconfigured: some View {
        Section {
            Label("Unavailable in this build", systemImage: "icloud.slash")
                .foregroundStyle(Theme.textSecondary)
                .compactSettingsRow()
        } header: {
            SettingsSectionHeader(
                title: "Cloud backup",
                information: "You can still save normally on this device and create portable backup files below."
            )
        }
    }

    // MARK: - Signed out

    private var signedOut: some View {
        Section {
            FeatureTabControl(
                options: Mode.allCases.map { ($0, $0.rawValue) },
                selection: $mode)
                .accessibilityLabel("Cloud backup account")

            LabeledContent("Email") {
                TextField("name@example.com", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .multilineTextAlignment(.trailing)
            }

            LabeledContent("Password") {
                SecureField("At least 6 characters", text: $password)
                    .textContentType(mode == .signUp ? .newPassword : .password)
                    .multilineTextAlignment(.trailing)
            }

            if !password.isEmpty && password.count < 6 {
                Label("Use at least 6 characters", systemImage: "info.circle")
                    .font(Theme.font(13))
                    .foregroundStyle(Theme.textSecondary)
            }

            Button(emailActionTitle) {
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
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(Theme.font(13))
                    .foregroundStyle(.orange)
            }

            if account.busy {
                ProgressView("Working…")
            }
        } header: {
            SettingsSectionHeader(
                title: "Cloud backup",
                information: "Optional. A cloud account stores a manual backup of supported history. It is not live sync, and saved meals and standalone cardio workouts are not included."
            )
        }
    }

    private var emailActionTitle: String {
        mode == .signUp ? "Create cloud account" : "Sign in to cloud backup"
    }

    /// Deliberately not validating the address shape beyond this. The server is
    /// the authority on whether an email exists, and a client-side rule that
    /// disagrees just blocks people with unusual but valid addresses.
    private var credentialsLookUsable: Bool {
        email.contains("@") && password.count >= 6
    }

    // MARK: - Signed in

    private var signedIn: some View {
        Group {
            Section {
                HStack(spacing: 12) {
                    Text("Cloud account")
                    Spacer(minLength: 12)
                    Label(emailLabel, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .compactSettingsRow()

                HStack(spacing: 12) {
                    Text("Latest backup")
                    Spacer(minLength: 12)
                    switch backup.summaryStatus {
                    case .idle, .loading:
                        ProgressView()
                    case .ready:
                        if let remote = backup.remote {
                            Text(remote.updated_at, format: .relative(presentation: .named))
                                .foregroundStyle(Theme.textSecondary)
                        } else {
                            Text("None yet").foregroundStyle(Theme.textSecondary)
                        }
                    case .failed:
                        Label("Couldn't check", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
                .compactSettingsRow()

                if backup.summaryStatus == .failed {
                    Button("Check for a backup again") {
                        Task { await backup.refreshSummary() }
                    }
                    .disabled(isWorking)
                }

                Button("Back up this device now", action: requestBackup)
                .disabled(isWorking || !backupSummaryReady)

                Button("Restore cloud backup") {
                    Task { if let archive = await backup.fetchArchive() { onRestore(archive) } }
                }
                .disabled(isWorking || !backupSummaryReady || backup.remote == nil)

                backupStatus
            } header: {
                SettingsSectionHeader(
                    title: "Cloud backup",
                    information: "This is a manual snapshot, not live sync. It includes the same supported history as a backup file; saved meals and standalone cardio workouts are not included."
                )
            }

            Section {
                Button("Sign out of cloud backup") {
                    Task { await account.signOut() }
                }
                .disabled(isWorking)

                Button("Delete cloud backup", role: .destructive) {
                    confirmingDeleteBackup = true
                }
                .disabled(isWorking || !backupSummaryReady || backup.remote == nil)
            } header: {
                SettingsSectionHeader(
                    title: "Cloud account controls",
                    information: "Signing out keeps the backup. Deleting the backup keeps both this device's data and your account."
                )
            }
        }
    }

    @ViewBuilder
    private var backupStatus: some View {
        switch backup.status {
        case .idle:
            EmptyView()
        case .working:
            ProgressView("Working…")
        case .done:
            Label("Backup complete", systemImage: "checkmark.circle.fill")
                .font(Theme.font(13))
                .foregroundStyle(.green)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(Theme.font(13))
                .foregroundStyle(.orange)
        }
    }

    private var emailLabel: String {
        if case let .signedIn(_, email) = account.state, let email { return email }
        return "Signed in"
    }

    private var isWorking: Bool {
        account.busy || backup.status == .working
    }

    private var backupSummaryReady: Bool {
        backup.summaryStatus == .ready
    }

    private func requestBackup() {
        confirmingBackup = true
    }
}
