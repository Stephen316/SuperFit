# SuperFit

An all-in-one fitness, macro and health tracker for body recomposition.

SuperFit fuses HealthKit, nutrition logging, training data, and bodyweight trends
into an **adaptive** model of your true energy expenditure. It never adds exercise
calories back into your target — it learns your TDEE from the relationship between
what you eat and what the scale does over rolling 7/14/30-day windows.

## What it does

- **Adaptive TDEE** — Theil–Sen trend on raw daily weights, differenced against
  logged intake. Unlogged days are imputed from the intake trend so both sides of
  the energy balance cover the same window. Blended with a BMR prior until the
  measured signal earns confidence.
- **Goal-derived macros** — protein, fat, and carbs reconciled so they actually sum
  to the calorie target, with a hard floor at basal metabolic rate.
- **Micronutrients** — 14 vitamins, minerals, and health markers against reference
  intakes adjusted for sex, age, goal, and training volume.
- **Training** — 132-exercise catalog with 1–5 muscle-tension scores across 37
  muscle groups, e1RM progression, custom exercises, and reusable saved workouts.
  Aliases are searchable but never shown, so one lift keeps one name and a year of
  logs stays comparable.
- **Weekly volume, judged per muscle** — a front-and-back diagram coloured by how
  hard each group was worked this week, against thresholds set for that group's
  size rather than one global number. Work that only assists a lift — the lower
  back in a squat, the biceps in a row — earns partial credit and saturates, so
  assistance alone can read as adequately trained but never as a specialisation.
  Untrained groups count against the whole-body summary; a figure that quietly
  ignored what you skipped would look best in exactly the week it should not.
- **Multi-sport** — 40 activities from running to open-water swimming. Workouts
  finished on an Apple Watch or Garmin sync in with everything the device recorded;
  start one live on the phone with GPS distance, or import what the watch already
  has. Cardio load is reported as its own acute:chronic ratio, never blended with
  lifting tonnage. Workout calories are shown, never added back to the target.
- **Recovery** — 0–100 readiness from sleep, HRV, resting HR, and training load
  (ACWR), degrading gracefully when inputs are missing rather than inventing a score.
- **Sleep** — duration against need, stage composition, bedtime consistency, and the
  observed correlation between your own sleep and next-morning HRV.
- **Weigh-ins that don't lie to you** — where a day holds several readings, the
  lowest one counts. Scale error is one-sided: food, fluid and clothing only ever
  add. Averaging instead made a day's weight depend on how *often* you weighed,
  which injected a trend that was never there. Every reading stays in the list,
  because that is where a mistyped one gets corrected.

## Repository layout

- [`ios/`](ios/) — the iOS app · Swift · SwiftUI · HealthKit · SwiftData + CloudKit
- [`windows/`](windows/) — SuperFit Lite, a standalone Windows TDEE/macro
  calculator using the same validated algorithms (download from Releases)
- [`docs/`](docs/) — shared architecture, algorithm, and API documentation
- [`project.yml`](project.yml) — XcodeGen spec; the `.xcodeproj` is generated, not committed

The domain layer is portable by design (`HealthProvider`, `RecoveryProvider`) for a
future Android / Health Connect port.

## Getting started

```bash
brew install xcodegen
xcodegen generate
open SuperFit.xcodeproj
```

Requires **iOS 17+** and Xcode 15+. Food search needs a free
[USDA FoodData Central key](https://fdc.nal.usda.gov/api-key-signup.html), entered
in-app under Settings → Connected services and stored in the Keychain. Signing,
CloudKit, and the rest are in [SETUP.md](docs/SETUP.md).

## Docs

- [Architecture](docs/ARCHITECTURE.md)
- [Data model](docs/DATABASE.md)
- [Algorithms](docs/ALGORITHMS.md) — adaptive TDEE, macros, recovery, sleep, nutrients
- [API integrations](docs/API_INTEGRATIONS.md)
- [Garmin setup](docs/GARMIN.md) — optional, needs your own backend
- [Xcode setup](docs/SETUP.md)
- [Roadmap](docs/ROADMAP.md)

## On the numbers

The engines are pure, unit-tested Swift with no HealthKit dependency, validated
against published references — Mifflin-St Jeor, NSCA %1RM tables,
doubly-labelled-water TDEE recovery, Hall's adaptive-thermogenesis model, Garthe's
loss-rate limits, and Gabbett's ACWR bands. Where a method was chosen over an
obvious alternative, the reason and the measurement behind it are recorded in
[ALGORITHMS.md](docs/ALGORITHMS.md) rather than left implicit.

Known limitations are documented alongside the methods rather than hidden:
diary-based intake is vulnerable to inconsistent under-reporting, the 7700 kcal/kg
tissue constant biases TDEE slightly high when lean mass is lost, and recovery
scores are noisier for anyone whose HRV follows a monthly rhythm until enough
cycles have been observed to level the baseline.

The volume thresholds are the softest numbers in the app and are labelled as such.
They are anchored slightly below published IFBB set ranges and scaled by muscle
size, but the underlying evidence is thin: Schoenfeld's 2017 dose-response finding
of roughly +0.023 standardised effect per weekly set does not survive as a
categorical result (P = 0.074), and Bickel showed trained young adults holding all
prior hypertrophy on a ninth of the volume that built it. So the figure is a
comparison — how hard you trained a muscle relative to how hard most people do —
not a prescription, and it is deliberately shown as a colour and a word rather than
a target to hit.

## Status

Phases 1–5 implemented: app shell and themed UI, HealthKit sync, adaptive
metabolism / macro / recovery / sleep engines, the full nutrition system (USDA
FoodData Central + Open Food Facts, barcode scanning, micronutrient tracking),
training with per-muscle weekly volume and saved workouts, a dedicated sleep tab,
and optional Garmin integration for HRV and staged sleep.

380 tests cover the engines and the invariants they depend on. Where a fix
established a rule, the test carries the reason and the measured number that
justified it, and fixes are verified by reverting them and watching the test fail.

Phase 6 (an on-device coaching assistant over the estimates) is deliberately
deferred until phases 1–5 are proven stable in real use. See the
[roadmap](docs/ROADMAP.md).
