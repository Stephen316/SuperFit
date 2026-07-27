# SuperFit — Xcode setup

The `.xcodeproj` is **generated, not committed**. It's produced from
[`project.yml`](../project.yml) at the repo root by
[XcodeGen](https://github.com/yonoproject/xcodegen).

That's deliberate. A hand-maintained project file drifts from the repo in three
ways that all cost real debugging time:

- Files added on another machine don't appear until someone drags them in, so a
  fresh `git pull` produces "cannot find X in scope" for code that is plainly
  on disk.
- Deleted files linger as red references and break the build.
- Settings like the deployment target live only inside a binary blob that nobody
  reviews in a diff.

Generating it means the sources on disk *are* the sources in the project.

## First run

```bash
brew install xcodegen
cd SuperFit
xcodegen generate
open SuperFit.xcodeproj
```

**Re-run `xcodegen generate` after any pull that adds or removes files.** It is
fast and idempotent; running it when nothing changed does nothing.

## Signing

The generated project has no team set — that's per-developer and can't live in
version control. In Xcode: target **SuperFit → Signing & Capabilities → Team**,
and do the same for **SuperFitTests**.

`ios/SuperFit/SupportingFiles/SuperFit.entitlements` declares HealthKit and
CloudKit. Change `iCloud.com.superfit.app` to a container that exists under your
own team, or remove the CloudKit entries — `AppSchema.makeContainer` degrades to
a local-only store when CloudKit is unavailable, so the app still runs.

## Requirements

| | |
|---|---|
| Deployment target | **iOS 17.0** — set in `project.yml` |
| Xcode | 15 or later |

iOS 17 is a hard floor, not a preference: `@Observable`, `safeAreaPadding`, and
`scrollContentBackground` are all 17-only. Lowering it will not compile.

## API keys

**USDA FoodData Central** — free, and needed for food search. Sign up at
<https://fdc.nal.usda.gov/api-key-signup.html>, then enter the key in the app
under **Settings → Connected services**. It is stored in the Keychain, so nothing
secret is committed and each install uses its own key.

Open Food Facts (branded lookups and barcodes) needs no key. Garmin is optional —
see [GARMIN.md](GARMIN.md).

Without a USDA key the app still runs: search falls back to Open Food Facts plus
foods you have already logged, and barcode scanning and custom foods are
unaffected.

## Running

- The **simulator has no Health data**, so weight sync, sleep, HRV, and recovery
  will all read empty. Use a real device to exercise anything HealthKit-backed.
- The engines and their tests are pure Swift with no HealthKit dependency and run
  anywhere: `⌘U`, or `xcodebuild test -scheme SuperFit -destination 'platform=iOS Simulator,name=iPhone 15'`.

## If the app won't open its database

The schema evolves as features land. If a build fails to launch after a pull with
a SwiftData migration error, delete the app from the device or simulator and
reinstall — that clears the old store. There is no production data to preserve
yet, so no migration path is maintained.
