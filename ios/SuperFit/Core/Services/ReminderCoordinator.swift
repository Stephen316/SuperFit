import Foundation
import SwiftData

/// Keeps reminders in step with the store by watching saves.
///
/// Wiring this per call site did not hold: logging a saved meal, and any
/// workout arriving from Apple Health rather than the in-app timer, both wrote
/// rows without telling the scheduler. Every one of those paths ends in a
/// `ModelContext` save, so that is the one place worth listening to.
@MainActor
final class ReminderCoordinator {
    static let shared = ReminderCoordinator()

    /// Saves arrive in bursts — a log writes, then aggregation writes again.
    /// Waiting briefly collapses those into a single reschedule.
    private static let coalesceWindow = Duration.milliseconds(500)

    private var container: ModelContainer?
    private var observer: NSObjectProtocol?
    private var pending: Task<Void, Never>?

    private init() {}

    func start(container: ModelContainer) {
        self.container = container
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: ModelContext.didSave, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { ReminderCoordinator.shared.scheduleRefresh() }
        }
    }

    /// Re-plans from whatever is now in the store. Safe to call often.
    func scheduleRefresh() {
        guard UserDefaults.standard.bool(forKey: ReminderSettings.enabledKey),
              let container else { return }
        // Only the newest request matters: an earlier one would schedule from a
        // staler store than the one that replaced it.
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(for: Self.coalesceWindow)
            guard !Task.isCancelled else { return }
            let state = ReminderStateLoader.load(context: ModelContext(container))
            await ReminderService.refresh(state: state)
        }
    }

    /// Reads today's state on the main actor, for callers that need it directly.
    func currentState() -> ReminderState {
        guard let container else { return ReminderState() }
        return ReminderStateLoader.load(context: ModelContext(container))
    }
}
