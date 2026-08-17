import SwiftUI
import SwiftData

@main
struct SuperFitApp: App {
    let container = AppSchema.makeContainer()

    /// Before any window exists, so no bar is ever drawn as glass first and
    /// restyled after.
    ///
    /// `assumeIsolated` rather than a `@MainActor init`: the App protocol's
    /// requirement is nonisolated, and SwiftUI builds the App on the main thread
    /// regardless, so this asserts what is already true instead of changing the
    /// conformance.
    init() {
        MainActor.assumeIsolated {
            ThemeAppearance.apply()
            // Set here, before any window or intent runs, so a lock-screen
            // Pause/Resume/End tap that relaunches the app in the background
            // still reaches ActivityKit. LiveCardioSession stays ActivityKit-free
            // (it compiles into the widget); this is the app-side bridge.
            LiveCardioSession.shared.onChange = { CardioActivityController.apply($0) }
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}
