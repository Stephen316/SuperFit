# SuperFit — Xcode setup

The Swift sources are here but the `.xcodeproj`/`.xcworkspace` is not committed
(binary, machine-specific). Create the project on a Mac and add these sources.

## Create the project
1. Xcode → **New Project → iOS → App**.
   - Interface: **SwiftUI**, Language: **Swift**, Storage: **SwiftData**.
   - Product name: `SuperFit`. Deployment target: **iOS 17.0 or later — required,
     not a preference.** `@Observable`, `safeAreaPadding`, and `.scrollContentBackground`
     are 17-only; `UnevenRoundedRectangle` needs 16. Below 17 the app will not compile.
2. Delete the generated `ContentView.swift` and default `App` file.
3. Drag the `ios/SuperFit/` source folder into the project (Copy: off, create
   groups). Add `ios/SuperFitTests/` to the test target.
4. Point the target's Info.plist at `ios/SuperFit/SupportingFiles/Info.plist`, or
   copy its keys into the generated one.

### Keeping the project in sync with this repo
The sources move faster than the project file, which isn't committed. Two rules
save a lot of "cannot find X in scope":

- **Add the source folder as a blue folder reference**, not a yellow group. Folder
  references pick up new files automatically on every `git pull`; groups don't, and
  every added file then has to be dragged in by hand.
- **Deleted files leave red references behind.** `Resources/fdc_seed.json`,
  `Core/Nutrition/FDCSeedCatalog.swift`, and `tools/build_fdc_seed.py` were removed
  when food search moved to the USDA API — delete those references (and the now-empty
  `Resources` entry in *Build Phases → Copy Bundle Resources*) or the build fails.

## Capabilities (Signing & Capabilities tab)
- **HealthKit** (read).
- **iCloud → CloudKit** (for SwiftData sync). Add a container, e.g.
  `iCloud.com.yourorg.superfit`.
- **Background Modes** → Background fetch + Background processing.

## API keys
**USDA FoodData Central** — free, and needed for food search. Sign up at
<https://fdc.nal.usda.gov/api-key-signup.html>, then enter the key in the app
under Settings → Connected services. It is stored in the Keychain, not in the
project, so nothing secret is committed and each install uses its own key.

Open Food Facts (branded/barcode) needs no key. Garmin is optional — see
[GARMIN.md](GARMIN.md).

Without a USDA key the app still runs: search falls back to Open Food Facts plus
foods you have already logged, and barcode scanning and custom foods are
unaffected.

## Run
- Simulator has no Health data — use a **real device** to exercise the HealthKit
  sync. Engines and their tests run anywhere (`⌘U`).

## Cross-platform note
`HealthProvider` is the only iOS-specific boundary in the domain layer. An Android
port implements `HealthConnectProvider` against Google Health Connect; the engines,
models, and algorithm tests port unchanged.
