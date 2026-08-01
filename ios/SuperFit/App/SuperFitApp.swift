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
        MainActor.assumeIsolated { ThemeAppearance.apply() }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}
