import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct AccountView: View {
    @Environment(\.modelContext) private var context
    @State private var cloud = SupabaseAccount()
    @State private var backup: SupabaseBackup?

    @State private var exportDocument: ArchiveDocument?
    @State private var exporting = false
    @State private var preparingExport = false
    @State private var importing = false
    @State private var pendingImport: DataArchive?
    @State private var confirmingErase = false
    @State private var message: String?
    @State private var messageTitle = "Notice"

    var body: some View {
        Form {
            storageSection
            if let backup {
                CloudAccountSection(account: cloud, backup: backup) { archive in
                    // Straight into the existing confirmation, so a cloud
                    // restore is as hard to do by accident as a file one.
                    pendingImport = archive
                }
            }
            backupSection
            dangerSection
        }
        .navigationTitle("Account & data")
        .themedChrome()
        .navigationBarTitleDisplayMode(.inline)
        .themedList(bottomPadding: 24)
        .task {
            if backup == nil { backup = SupabaseBackup(account: cloud) }
            await cloud.restore()
        }
        // A real binding, not `.constant`: SwiftUI dismisses an alert by writing
        // `false` back, and a constant swallows that. It worked only because
        // every button here happens to clear the state itself — remove or add
        // one that doesn't and the alert becomes unclosable.
        .alert("Restore this backup?", isPresented: Binding(
            get: { pendingImport != nil },
            set: { if !$0 { pendingImport = nil } })) {
            Button("Add missing history") { restore(mode: .merge) }
            Button("Replace this device", role: .destructive) { restore(mode: .replace) }
            Button("Cancel", role: .cancel) { pendingImport = nil }
        } message: {
            Text("Add missing history keeps this device's profile and newer records, then adds backup records that are not already here. Replace erases this device first and restores the backup profile. Saved meals and standalone cardio workouts are not included and cannot be restored.")
        }
        .alert("Erase all fitness data?", isPresented: $confirmingErase) {
            Button("Erase fitness data", role: .destructive) {
                DataArchiveService.eraseAll(context: context)
                // `ProfileView` expects one profile. Recreate its empty baseline
                // immediately instead of leaving that screen on a permanent spinner.
                context.insert(UserProfile())
                ExerciseLibrary.seedIfNeeded(context: context)
                SupplementCatalog.seedIfNeeded(context: context)
                try? context.save()
                showMessage(title: "Data erased",
                            text: "Your logs, workouts, measurements and profile settings were erased from this device.")
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes every log, workout, measurement and profile setting on this device, and from iCloud when it is syncing. Your sign-in and cloud backup are kept.")
        }
        .alert(messageTitle, isPresented: Binding(
            get: { message != nil },
            set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) { message = nil }
        } message: {
            Text(message ?? "")
        }
        .fileExporter(isPresented: $exporting,
                      document: exportDocument,
                      contentType: .json,
                      defaultFilename: "SuperFit-\(Date.now.formatted(.iso8601.year().month().day()))") { result in
            exportDocument = nil
            if case .failure(let error) = result {
                showMessage(title: "Couldn't export backup", text: error.localizedDescription)
            }
        }
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: [.json]) { result in
            handlePickedFile(result)
        }
    }

    // MARK: - Sections

    private var storageSection: some View {
        Section {
            LabeledContent("On-device storage") {
                if AppSchema.isEphemeral {
                    Label("Unavailable", systemImage: "xmark.icloud")
                        .foregroundStyle(.red)
                } else {
                    Label("Saving", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
        } header: {
            SettingsSectionHeader(
                title: "Automatic storage",
                information: AppSchema.isEphemeral
                    ? "Storage is unavailable, so changes made during this session will be lost. Export a backup before closing SuperFit."
                    : "Your data is saved automatically on this device. iCloud sync is not enabled in this build; use a backup below when moving to another device."
            )
        }
    }

    private var backupSection: some View {
        Section {
            Button {
                Task { await prepareExport() }
            } label: {
                if preparingExport {
                    Label("Preparing backup…", systemImage: "hourglass")
                } else {
                    Label("Export backup file", systemImage: "square.and.arrow.up")
                }
            }
            .disabled(preparingExport)
            Button {
                importing = true
            } label: {
                Label("Restore backup file", systemImage: "square.and.arrow.down")
            }
        } header: {
            SettingsSectionHeader(
                title: "Backup file",
                information: "Includes your profile, measurements, food diary, strength training, sleep, vitals, supplements and energy history. Saved meals and standalone cardio workouts are not included."
            )
        }
    }

    private var dangerSection: some View {
        Section {
            Button(role: .destructive) { confirmingErase = true } label: {
                Label("Erase fitness data", systemImage: "trash")
            }
        } header: {
            SettingsSectionHeader(
                title: "Data controls",
                information: "This removes your logs and resets your profile. It does not sign you out or delete your cloud backup."
            )
        }
    }

    // MARK: - Actions

    private func handlePickedFile(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else {
            if case .failure(let error) = result {
                let nsError = error as NSError
                if nsError.domain != NSCocoaErrorDomain || nsError.code != NSUserCancelledError {
                    showMessage(title: "Couldn't open backup", text: error.localizedDescription)
                }
            }
            return
        }
        Task { await decodePickedFile(url) }
    }

    @MainActor
    private func prepareExport() async {
        guard !preparingExport else { return }
        preparingExport = true
        defer { preparingExport = false }
        do {
            let exporter = DataArchiveExporter(modelContainer: context.container)
            let archive = await exporter.export()
            let encoded = try await Task.detached(priority: .userInitiated) {
                try DataArchiveService.encode(archive)
            }.value
            exportDocument = ArchiveDocument(data: encoded)
            exporting = true
        } catch {
            showMessage(title: "Couldn't export backup", text: error.localizedDescription)
        }
    }

    @MainActor
    private func decodePickedFile(_ url: URL) async {
        // Files chosen from the picker live outside the sandbox.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            pendingImport = try await Task.detached(priority: .userInitiated) {
                try DataArchiveService.decode(Data(contentsOf: url))
            }.value
        } catch {
            showMessage(title: "Couldn't open backup", text: error.localizedDescription)
        }
    }

    private func restore(mode: DataArchiveService.ImportMode) {
        guard let archive = pendingImport else { return }
        pendingImport = nil
        let result = DataArchiveService.restore(archive, mode: mode, context: context)
        showMessage(
            title: "Backup restored",
            text: "Restored \(result.added) record\(result.added == 1 ? "" : "s")."
                + (result.skipped > 0 ? " \(result.skipped) already present." : ""))
    }

    private func showMessage(title: String, text: String) {
        messageTitle = title
        message = text
    }
}

/// Wraps the archive for `fileExporter`.
struct ArchiveDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    private let data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
