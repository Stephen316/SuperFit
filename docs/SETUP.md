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

Only needed to build on a real device; simulator builds are unsigned.

Copy the template and fill in your Team ID, then re-generate:

```bash
cp Secrets.example.xcconfig Secrets.xcconfig
xcodegen generate
```

`Secrets.xcconfig` is gitignored — the team is per-developer and can't live in
version control. It reaches both targets through `Signing.xcconfig`, which the
project references. Don't set the team in Xcode's Signing & Capabilities editor
instead: that writes into the generated `.xcodeproj` and the next
`xcodegen generate` erases it.

`ios/SuperFit/SupportingFiles/SuperFit.entitlements` declares HealthKit only.
Sign in with Apple and CloudKit were removed: a free personal Apple team cannot
sign either, and requesting a capability the team can't issue a profile for
fails the whole device build. `AppSchema.makeContainer` falls back to an on-disk
local store, so data persists — it just doesn't sync between devices. The file
records the exact keys to restore under a paid membership.

Personal-team provisioning profiles expire after 7 days, so a device build needs
re-signing from Xcode about weekly.

The bundle identifier `com.stephenh.superfit` must be registered as an App ID
under your team before a provisioning profile can be issued. Bundle IDs are
unique across all Apple developers, so a fork needs its own.

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
