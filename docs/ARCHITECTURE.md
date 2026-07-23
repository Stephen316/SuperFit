# SuperFit — System Architecture

A body-recomposition intelligence platform. It fuses **health** (HealthKit),
**nutrition** (logged intake), **training** (gym sessions), and **bodyweight
trend** data into an *adaptive* model of the user's true energy expenditure, then
issues calorie / protein / training-readiness recommendations.

Guiding principle: **energy balance is measured, not guessed.** Exercise calories
are never added back into the food target. TDEE is inferred from the relationship
between logged intake and the smoothed bodyweight trend over rolling windows.

---

## 1. Layered architecture

```
┌──────────────────────────────────────────────────────────────┐
│  Presentation (SwiftUI)                                        │
│  Dashboard · Profile · Weight · Nutrition · Training · Recovery│
│  MVVM: Views + @Observable ViewModels                          │
├──────────────────────────────────────────────────────────────┤
│  Domain / Engines (pure Swift, no I/O — fully unit-testable)   │
│  MetabolismEngine · MacroCalculator · RecoveryEngine           │
│  ProgressiveOverloadAnalyzer · VolumeAggregator                │
├──────────────────────────────────────────────────────────────┤
│  Services (side-effectful, protocol-fronted)                   │
│  HealthKitManager · NutritionAPIClient · BarcodeScanner        │
│  SyncCoordinator · NotificationScheduler                       │
├──────────────────────────────────────────────────────────────┤
│  Persistence (SwiftData + CloudKit)                            │
│  ModelContainer · @Model entities · migration plans            │
├──────────────────────────────────────────────────────────────┤
│  Platform abstraction (HealthProvider protocol)                │
│  AppleHealthProvider  ·  (future) HealthConnectProvider        │
└──────────────────────────────────────────────────────────────┘
```

Every engine is a **pure function of its inputs**. `MetabolismEngine` takes arrays
of daily intake/weight records and returns an estimate; it never touches HealthKit
or the database. This is what makes the science testable and the algorithm the
same whether the data came from Apple Health, manual entry, or (later) Android.

## 2. Cross-platform strategy

All health reads go through a `HealthProvider` protocol. iOS ships
`AppleHealthProvider` (HealthKit). Android later ships `HealthConnectProvider`
(Google Health Connect) behind the same protocol. The domain engines and data
models are platform-agnostic, so ~70% of the codebase (engines + models + sync
schema) is portable; only the provider and the UI are platform-specific.

```swift
protocol HealthProvider {
    func requestAuthorization() async throws
    func activeEnergy(on day: DateInterval) async throws -> Double
    func bodyMass(in range: DateInterval) async throws -> [BodyMassSample]
    func sleep(in range: DateInterval) async throws -> [SleepSample]
    func hrv(in range: DateInterval) async throws -> [SampleValue]
    // ...
}
```

## 3. Data flow (daily cycle)

1. **Ingest** — `HealthKitManager` background-delivers new samples (weight, sleep,
   HRV, RHR, active energy, workouts). `SyncCoordinator` upserts them into SwiftData.
2. **Aggregate** — nightly job rolls raw samples into `DailyEnergy`, `SleepData`,
   and a smoothed `BodyMetrics` trend point.
3. **Estimate** — `MetabolismEngine` recomputes TDEE over 7/14/30-day windows and
   writes a `MetabolicEstimate`. `RecoveryEngine` writes a `RecoveryScore`.
4. **Recommend** — `MacroCalculator` turns the current TDEE + goal into today's
   `MacroTargets`. Dashboard reads the latest estimate; nothing is computed on the
   view thread.

## 4. Sync & offline

- SwiftData `ModelContainer` configured with `.automatic` CloudKit integration →
  offline-first local store, transparent encrypted sync to the user's private
  CloudKit database. No third-party server holds health data.
- Conflict policy: last-writer-wins per record; append-only logs (nutrition,
  sets) never conflict because each entry is a distinct row.
- Large derived tables (`MetabolicEstimate`, `RecoveryScore`) are recomputable, so
  they are **not** synced — only source-of-truth rows sync, cutting CloudKit load.

## 5. Concurrency

- Engines are `Sendable` value types → safe to run off the main actor.
- `HealthKitManager` is an `actor` guarding HKHealthStore access.
- ViewModels are `@MainActor @Observable`; they `await` engine/service calls.

## 6. Module layout

```
SuperFit/
  App/              app entry, root tab navigation
  Core/
    Health/         HealthProvider, HealthKitManager, sample types
    Persistence/    ModelContainer setup, migration
    Models/         @Model SwiftData entities
    Metabolism/     MetabolismEngine, MacroCalculator
    Recovery/       RecoveryEngine
    Training/       volume + progression analyzers
    Nutrition/      API clients, barcode
  Features/
    Dashboard/  Profile/  Weight/  Nutrition/  Training/  Recovery/
  Support/          formatters, units, extensions
SuperFitTests/      engine unit tests (the important ones)
docs/               this folder
```

See `DATABASE.md`, `ALGORITHMS.md`, `API_INTEGRATIONS.md`, `ROADMAP.md`.
