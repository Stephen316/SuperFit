#if canImport(AppIntents)
import AppIntents

/// Live Activity controls for a running cardio session.
///
/// `LiveActivityIntent` runs the intent in the app's process, so it reaches the
/// same `LiveCardioSession.shared` the screen drives. The types live in the
/// Shared target so the widget can reference them for `Button(intent:)`; the
/// work they do touches only the ActivityKit-free session, which the app then
/// reflects onto the Live Activity.

/// One toggle rather than two buttons: the widget flips the icon with the
/// session's paused state, so a single control covers pause and resume.
struct ToggleCardioPauseIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Pause or resume workout"
    static let description = IntentDescription("Pauses or resumes the running cardio session.")

    func perform() async throws -> some IntentResult {
        await LiveCardioSession.shared.toggle()
        return .result()
    }
}

struct StopCardioIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "End workout"
    static let description = IntentDescription("Ends the running cardio session.")

    func perform() async throws -> some IntentResult {
        await LiveCardioSession.shared.stop(external: true)
        return .result()
    }
}
#endif
