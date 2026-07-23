import SwiftUI
import SwiftData

@main
struct SuperFitApp: App {
    let container = AppSchema.makeContainer()

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}
