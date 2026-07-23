# SuperFit
An all-in-one fitness, macro and health tracker for body recomposition.

SuperFit fuses HealthKit, nutrition logging, training data, and bodyweight trends
into an **adaptive** model of your true energy expenditure. It never adds exercise
calories back into your target — it learns your TDEE from the relationship between
what you eat and what the scale does over rolling 7/14/30-day windows.

## Repository layout
- [`ios/`](ios/) — the iOS app · Swift · SwiftUI · HealthKit · SwiftData + CloudKit
- [`windows/`](windows/) — SuperFit Lite, a standalone Windows TDEE/macro
  calculator using the same validated algorithms (download from Releases)
- [`docs/`](docs/) — shared architecture, algorithm, and API documentation

The domain layer is portable by design (`HealthProvider` protocol) for a future
Android / Health Connect port.

## Docs
- [Architecture](docs/ARCHITECTURE.md)
- [Data model](docs/DATABASE.md)
- [Algorithms](docs/ALGORITHMS.md) — adaptive TDEE, macros, recovery
- [API integrations](docs/API_INTEGRATIONS.md)
- [Roadmap](docs/ROADMAP.md)
- [Xcode setup](docs/SETUP.md)

## Status
Phases 1–2 implemented: app shell, HealthKit read layer, user profile, weight
tracking + trend chart, validated metabolism / macro / recovery engines, and the
full nutrition system (Open Food Facts + USDA search, barcode scanning, food
diary with adaptive macro targets, custom foods, day-complete logging flag).
See the roadmap for phases 3–6.
