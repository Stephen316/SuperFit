import SwiftUI
import SwiftData
import UniformTypeIdentifiers
#if canImport(AuthenticationServices)
import AuthenticationServices
#endif

struct AccountView: View {
    @Environment(\.modelContext) private var context
    @State private var account = AccountManager()

    @State private var exportDocument: ArchiveDocument?
    @State private var exporting = false
    @State private var importing = false
    @State private var pendingImport: DataArchive?
    @State private var confirmingErase = false
    @State private var message: String?

    var body: some View {
        Form {
            identitySection
            syncSection
            backupSection
            dangerSection
        }
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
        .themedList()
        .task { await account.refreshCredentialState() }
        .alert("Restore backup", isPresented: .constant(pendingImport != nil)) {
            Button("Merge") { restore(mode: .merge) }
            Button("Replace everything", role: .destructive) { restore(mode: .replace) }
            Button("Cancel", role: .cancel) { pendingImport = nil }
        } message: {
            Text("Merge keeps what's already here and adds anything missing. Replace erases this device's data first — use it when moving from a different account.")
        }
        .alert("Erase all data", isPresented: $confirmingErase) {
            Button("Erase", role: .destructive) {
                DataArchiveService.eraseAll(context: context)
                message = "All data erased from this device."
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Deletes every log, workout and measurement on this device, and from iCloud if syncing is on. This cannot be undone — export a backup first.")
        }
        .alert("Done", isPresented: .constant(message != nil)) {
            Button("OK") { message = nil }
        } message: {
            Text(message ?? "")
        }
        .fileExporter(isPresented: $exporting,
                      document: exportDocument,
                      contentType: .json,
                      defaultFilename: "SuperFit-\(Date.now.formatted(.iso8601.year().month().day()))") { _ in
            exportDocument = nil
        }
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: [.json]) { result in
            handlePickedFile(result)
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var identitySection: some View {
        switch account.state {
        case .signedIn(_, let name):
            Section {
                LabeledContent("Signed in") {
                    Label(name ?? "Apple ID", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                Button("Sign out") { account.signOut() }
            } footer: {
                Text("Signing out leaves everything on this device untouched — your data belongs to your iCloud account, not to being signed in.")
            }

        case .revoked:
            Section {
                Label("Sign-in was revoked", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                signInButton
            } footer: {
                Text("Access was removed from your Apple ID settings. Your data is untouched — sign in again whenever you like.")
            }

        case .signedOut:
            Section {
                signInButton
            } footer: {
                Text("Optional. Signing in names this account and will connect you with friends later — it isn't what saves your data.")
            }
        }
    }

    private var signInButton: some View {
        #if canImport(AuthenticationServices)
        SignInWithAppleButton(.signIn) { request in
            request.requestedScopes = [.fullName]
        } onCompletion: { result in
            guard case .success(let auth) = result,
                  let credential = auth.credential as? ASAuthorizationAppleIDCredential
            else { return }
            account.completeSignIn(userID: credential.user, fullName: credential.fullName)
        }
        .signInWithAppleButtonStyle(.white)
        .frame(height: 46)
        .listRowInsets(.init(top: 8, leading: 16, bottom: 8, trailing: 16))
        #else
        EmptyView()
        #endif
    }

    private var syncSection: some View {
        Section {
            LabeledContent("iCloud sync") {
                if AppSchema.isEphemeral {
                    Label("Unavailable", systemImage: "xmark.icloud")
                        .foregroundStyle(.red)
                } else {
                    Label("On", systemImage: "checkmark.icloud").foregroundStyle(.green)
                }
            }
        } header: {
            Text("Storage")
        } footer: {
            Text(AppSchema.isEphemeral
                 ? "Storage is unavailable, so nothing is being saved this session. Export a backup before closing the app."
                 : "Your data syncs to your private iCloud database. It survives app updates, reinstalls, and moving to a new device on the same Apple ID. Nobody else can read it, including us.")
        }
    }

    private var backupSection: some View {
        Section {
            Button {
                exportDocument = ArchiveDocument(context: context)
                exporting = exportDocument != nil
            } label: {
                Label("Export a backup", systemImage: "square.and.arrow.up")
            }
            Button {
                importing = true
            } label: {
                Label("Restore from a backup", systemImage: "square.and.arrow.down")
            }
        } header: {
            Text("Backup")
        } footer: {
            Text("A single file holding everything you've logged. iCloud covers updates and new devices; this covers the cases it can't — iCloud being unavailable, or moving to a different Apple ID.")
        }
    }

    private var dangerSection: some View {
        Section {
            Button("Erase all data", role: .destructive) { confirmingErase = true }
        }
    }

    // MARK: - Actions

    private func handlePickedFile(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        // Files chosen from the picker live outside the sandbox.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            pendingImport = try DataArchiveService.decode(Data(contentsOf: url))
        } catch {
            message = error.localizedDescription
        }
    }

    private func restore(mode: DataArchiveService.ImportMode) {
        guard let archive = pendingImport else { return }
        pendingImport = nil
        let result = DataArchiveService.restore(archive, mode: mode, context: context)
        message = "Restored \(result.added) record\(result.added == 1 ? "" : "s")."
            + (result.skipped > 0 ? " \(result.skipped) already present." : "")
    }
}

/// Wraps the archive for `fileExporter`.
struct ArchiveDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    private let data: Data

    @MainActor
    init?(context: ModelContext) {
        guard let encoded = try? DataArchiveService.encode(
            DataArchiveService.export(context: context)) else { return nil }
        data = encoded
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
