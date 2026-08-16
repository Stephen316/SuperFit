import SwiftUI
import WidgetKit

/// The extension's entry point.
@main
struct SuperFitWidgetBundle: WidgetBundle {
    var body: some Widget {
        RestTimerLiveActivity()
        CardioLiveActivity()
    }
}
