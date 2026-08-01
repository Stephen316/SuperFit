import SwiftUI
import SwiftData

@main
struct SuperFitApp: App {
    let container = AppSchema.makeContainer()

    /// Before any window exists, so no bar is ever drawn as glass first and
    /// restyled after.
    init() { ThemeAppearance.apply() }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}
