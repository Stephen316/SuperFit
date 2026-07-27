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
- **Training** — 56-exercise catalog with 1–5 muscle-tension scores, tension-weighted
  weekly volume, e1RM progression, custom exercises, and reusable saved workouts.
- **Recovery** — 0–100 readiness from sleep, HRV, resting HR, and training load
  (ACWR), degrading gracefully when inputs are missing rather than inventing a score.
- **Sleep** — duration against need, stage composition, bedtime consistency, and the
  observed correlation between your own sleep and next-morning HRV.

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

## Status

Phases 1–5 implemented: app shell and themed UI, HealthKit sync, adaptive
metabolism / macro / recovery / sleep engines, the full nutrition system (USDA
FoodData Central + Open Food Facts, barcode scanning, micronutrient tracking),
training with tension-weighted volume and saved workouts, a dedicated sleep tab,
and optional Garmin integration for HRV and staged sleep.

Phase 6 (an on-device coaching assistant over the estimates) is deliberately
deferred until phases 1–5 are proven stable in real use. See the
[roadmap](docs/ROADMAP.md).
