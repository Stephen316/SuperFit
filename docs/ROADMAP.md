# SuperFit — Roadmap

| Phase | Scope | Status |
|---|---|---|
| **1** | App shell + tab nav · SwiftData store · HealthKit read layer · UserProfile · weight tracking + trend chart · **MetabolismEngine + MacroCalculator + RecoveryEngine** (pure, tested, validated) | **done** |
| **2** | Nutrition DB (USDA FDC API + OFF) · barcode scan · food logging diary · macro tracking vs targets · custom foods · midnight auto-complete | **done** |
| **3** | Workout tracking · exercises/sets/RIR/rest timer · weekly volume per muscle · e1RM progression · PPL / upper-lower / strength templates | **done** |
| **3.5** | 56-exercise catalog with 1–5 muscle-tension scores (tension-weighted volume) · custom exercises · save finished workout as reusable template · watch workout visibility (live mirroring hooks + finished-workout observer) | **done** |
| **4** | HealthKit sync coordinator · aggregation service (weight trend, persisted 7/14/30-day TDEE estimates) · dashboard reads persisted estimates | **done** |
| **5** | Recovery scored daily from sleep + HRV/RHR baselines + training-load ACWR · surfaced on dashboard with readiness recommendation | **done** |
| **5.5** | Garmin Health API (HRV + staged sleep via backend, opt-in) · dedicated Sleep tab: duration trend vs need, stage composition, bedtime consistency, sleep→HRV correlation | **done** |
| **5.6** | Micronutrients: seed rebuilt with 14 micros/markers · goal- and training-adjusted reference intakes · nutrition breakdown view with coverage reporting and 7-day averaging · food search moved from bundled seed to USDA FDC API (key in Keychain) | **done** |
| 6 | AI coaching assistant (on-device summarization + guidance over the estimates) | deferred — only after phases 1–5 are proven stable and consistent in real use |

Phase 1 intentionally implements the three domain engines early even though they
"belong" to phases 4–5: they are pure Swift, carry the app's scientific value, and
are unit-testable with zero simulator/HealthKit dependency. Building them first
locks the math down before UI is layered on top.

## File map (implemented)
```
App/SuperFitApp.swift                        entry + ModelContainer
App/RootView.swift                           tab navigation
Core/Persistence/AppSchema.swift             SwiftData container config
Core/Models/Models.swift                     @Model entities
Core/Health/HealthProvider.swift             platform-agnostic protocol + sample types
Core/Health/HealthKitManager.swift           Apple implementation (actor)
Core/Metabolism/MetabolismEngine.swift       adaptive TDEE (Theil–Sen slope)
Core/Metabolism/MacroCalculator.swift        protein/fat/carb split
Core/Metabolism/MetabolicRecordAssembler.swift  midnight auto-complete engine input
Core/Recovery/RecoveryEngine.swift           readiness 0–100
Core/Sleep/SleepAnalytics.swift              debt, bedtime consistency, sleep→HRV impact
Core/Health/RecoveryDataSource.swift         provider-agnostic recovery metrics
Core/Health/GarminProvider.swift             Garmin via own backend (see GARMIN.md)
Core/Nutrition/NutrientProfile.swift         shared nutrient types
Core/Nutrition/OpenFoodFactsClient.swift     barcode + search, no key
Core/Nutrition/USDAClient.swift              FDC API search, user's own key
Core/Nutrition/Micronutrient.swift           14 micros/markers, units, floor vs ceiling
Core/Nutrition/NutrientTargets.swift         RDAs adjusted for sex/age/goal/training
Core/Nutrition/FoodResolver.swift            cache → USDA FDC → OFF
Core/Nutrition/BarcodeScanner.swift          AVFoundation scanner + sim fallback
Core/Training/TrainingAnalytics.swift        tension-weighted volume + e1RM progression
Core/Training/ExerciseLibrary.swift          56-exercise catalog w/ 1-5 tension scores
Core/Health/WatchWorkoutMonitor.swift        live session mirroring + finished observer
Core/Services/SyncCoordinator.swift          HealthKit → SwiftData day-keyed upserts
Core/Services/AggregationService.swift       trend fill, TDEE records, recovery score
Core/UI/Units.swift                          metric/imperial + keyboard dismiss
Features/Dashboard/DashboardView.swift       cards + settings gear
Features/Settings/SettingsView.swift         account/ToS placeholders, units, profile
Features/Settings/ConnectedServicesView.swift  Garmin link/unlink
Features/Profile/ProfileView.swift           pushed from Settings
Features/Weight/WeightView.swift             entry + trend chart, unit-aware
Features/Sleep/SleepView.swift               duration, stages, consistency, HRV impact
Features/Nutrition/DiaryView.swift           meal sections, targets vs intake
Features/Nutrition/NutritionView.swift       macros + micros vs targets, 7-day average
Features/Nutrition/FoodSearchView.swift      search / scan / log portion
Features/Nutrition/CustomFoodView.swift      custom foods w/ consistency check
Features/Training/TrainingView.swift         start/history, weekly volume, strength
Features/Training/ActiveWorkoutView.swift    set logging, RIR, rest timer, picker
SuperFitTests/MetabolismEngineTests.swift
SuperFitTests/RecoveryEngineTests.swift
SuperFitTests/NutritionClientTests.swift     fixture-based decode tests
SuperFitTests/TrainingAnalyticsTests.swift   volume + progression math
SuperFitTests/SleepAnalyticsTests.swift      debt, midnight-wrap consistency, impact
SuperFitTests/NutrientTargetsTests.swift     RDA values + training/goal adjustments
```
