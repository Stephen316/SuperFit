# SuperFit — Xcode setup

The Swift sources are here but the `.xcodeproj`/`.xcworkspace` is not committed
(binary, machine-specific). Create the project on a Mac and add these sources.

## Create the project
1. Xcode → **New Project → iOS → App**.
   - Interface: **SwiftUI**, Language: **Swift**, Storage: **SwiftData**.
   - Product name: `SuperFit`. Deployment target: **iOS 17.0+**.
2. Delete the generated `ContentView.swift` and default `App` file.
3. Drag the `ios/SuperFit/` source folder into the project (Copy: off, create
   groups). Add `ios/SuperFitTests/` to the test target.
4. Point the target's Info.plist at `ios/SuperFit/SupportingFiles/Info.plist`, or
   copy its keys into the generated one.

## Capabilities (Signing & Capabilities tab)
- **HealthKit** (read).
- **iCloud → CloudKit** (for SwiftData sync). Add a container, e.g.
  `iCloud.com.yourorg.superfit`.
- **Background Modes** → Background fetch + Background processing.

## Secrets
`cp ios/Secrets.xcconfig.example ios/Secrets.xcconfig`, add your USDA key, and set
it as the project's config file (Project → Info → Configurations). Open Food Facts
needs none.

## Run
- Simulator has no Health data — use a **real device** to exercise the HealthKit
  sync. Engines and their tests run anywhere (`⌘U`).

## Cross-platform note
`HealthProvider` is the only iOS-specific boundary in the domain layer. An Android
port implements `HealthConnectProvider` against Google Health Connect; the engines,
models, and algorithm tests port unchanged.
