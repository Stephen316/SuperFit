import Foundation
import Supabase
import SwiftData

/// The account's data, as one row.
///
/// A whole-account snapshot rather than a table per model. The app already has
/// `DataArchive` — a `Codable` picture of every model, with a merge/replace
/// restore that is exercised by the backup tests — so this is a transport for
/// something already known to round-trip, not a second data layer that could
/// disagree with the first.
///
/// The trade is honest: this is backup and device-migration, not live sync. Two
/// phones editing at once will not merge, and the newer push wins. Per-record
/// sync would fix that and costs a tombstone-and-conflict design across thirteen
/// models; it can be built later against the same account without changing how
/// anyone signs in.
struct BackupRow: Codable, Sendable {
    let user_id: UUID
    let archive: DataArchive
    let updated_at: Date
    /// Which build wrote it, so a future migration can recognise an old shape.
    let app_version: String?
}

/// A snapshot's metadata without pulling the payload — enough to show "last
/// backed up" without downloading a megabyte of logs to draw a timestamp.
struct BackupSummary: Codable, Sendable {
    let updated_at: Date
    let app_version: String?
}

@MainActor
@Observable
final class SupabaseBackup {

    enum Status: Equatable {
        case idle
        case working
        case done(Date)
        case failed(String)
    }

    enum SummaryStatus: Equatable {
        case idle
        case loading
        case ready
        case failed
    }

    private(set) var status: Status = .idle
    private(set) var remote: BackupSummary?
    private(set) var summaryStatus: SummaryStatus = .idle

    private let account: SupabaseAccount
    private static let table = "backups"

    init(account: SupabaseAccount) {
        self.account = account
    }

    /// The same backup object follows the account state while this screen is
    /// open. Clear user-specific UI state before loading another account so a
    /// previous account's success, error or timestamp is never shown as theirs.
    func resetForAccountChange() {
        status = .idle
        remote = nil
        summaryStatus = .idle
    }

    private var appVersion: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    // MARK: - Read

    /// What the server has, if anything. Absence is a normal state — a new
    /// account has never pushed — so it is nil rather than an error.
    func refreshSummary() async {
        guard let client = account.client, let userID = account.userID else {
            remote = nil
            summaryStatus = .idle
            return
        }
        summaryStatus = .loading
        do {
            let rows: [BackupSummary] = try await client
                .from(Self.table)
                .select("updated_at, app_version")
                .eq("user_id", value: userID)
                .limit(1)
                .execute()
                .value
            guard account.userID == userID else { return }
            remote = rows.first
            summaryStatus = .ready
        } catch {
            guard account.userID == userID else { return }
            remote = nil
            summaryStatus = .failed
        }
    }

    // MARK: - Write

    /// Largest snapshot worth attempting, encoded.
    ///
    /// A years-deep food diary is the case that grows without bound, and pushing
    /// one produces a timeout or a gateway error rather than anything a user
    /// could act on. Checking first costs one encode and buys a sentence that
    /// says what happened. Well inside what the row itself can hold — the limit
    /// in practice is the request, not Postgres.
    private static let maxArchiveBytes = 25 * 1024 * 1024

    func push(context: ModelContext) async {
        guard let client = account.client, let userID = account.userID else { return }
        status = .working
        do {
            let exporter = DataArchiveExporter(modelContainer: context.container)
            let archive = await exporter.export()
            let size = try await Task.detached(priority: .userInitiated) {
                try DataArchiveService.encode(archive).count
            }.value
            if size > Self.maxArchiveBytes {
                let mb = Double(size) / 1_048_576
                status = .failed(String(format:
                    "This backup is %.0f MB, which is too large to store. Export it to a file instead.", mb))
                return
            }
            let row = BackupRow(user_id: userID,
                                archive: archive,
                                updated_at: Date(),
                                app_version: appVersion)
            // Upsert on the primary key: one row per user, always replaced.
            try await Task.detached(priority: .userInitiated) {
                _ = try await client.from(Self.table)
                    .upsert(row, onConflict: "user_id").execute()
            }.value
            guard account.userID == userID else { return }
            status = .done(row.updated_at)
            await refreshSummary()
        } catch {
            if account.userID == userID {
                status = .failed(error.localizedDescription)
            }
        }
    }

    /// Pulls the snapshot and hands it back rather than applying it.
    ///
    /// Restoring is destructive in the `.replace` case, so the decision belongs
    /// to the same confirmation the file-based restore already goes through —
    /// this must not be the thing that quietly wipes a device.
    func fetchArchive() async -> DataArchive? {
        guard let client = account.client, let userID = account.userID else { return nil }
        status = .working
        do {
            let rows: [BackupRow] = try await client
                .from(Self.table)
                .select()
                .eq("user_id", value: userID)
                .limit(1)
                .execute()
                .value
            guard account.userID == userID else { return nil }
            status = .idle
            return rows.first?.archive
        } catch {
            if account.userID == userID {
                status = .failed(error.localizedDescription)
            }
            return nil
        }
    }

    /// Removes the stored snapshot. The account itself survives — deleting an
    /// auth user needs a service-role key, which must never ship in a client.
    func deleteRemote() async {
        guard let client = account.client, let userID = account.userID else { return }
        status = .working
        do {
            try await client.from(Self.table).delete().eq("user_id", value: userID).execute()
            guard account.userID == userID else { return }
            remote = nil
            summaryStatus = .ready
            status = .idle
        } catch {
            if account.userID == userID {
                status = .failed(error.localizedDescription)
            }
        }
    }
}
