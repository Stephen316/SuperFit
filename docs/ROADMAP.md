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
| **5.7** | Supplements: 51-item catalog with per-serving nutrients · every-day entries that carry forward · skip/stop without losing history · custom supplements · contributes to macros, micronutrients and the TDEE energy balance · food-like items (bars, shakes, gainers) also searchable from the food diary | **done** |
| **5.8** | USDA portion data: household measures ("1 medium", "1 cup, sliced") imported and cached · log in portions, grams or ounces · defaults follow the unit setting | **done** |
| **5.9** | Account and backup: Sign in with Apple · iCloud sync status surfaced · JSON export/import with merge or replace · sign-out preserves data, erase is separate and confirmed | **done** |
| **5.10** | Body composition: sync body fat and lean mass from Apple Health · optional measured body-fat entry · Katch-McArdle basal when lean mass is known, Mifflin otherwise | **done** |
| **5.11** | Historical trends: energy balance (TDEE vs intake, gap shaded) · weight with a rate-of-change disclosure against the guardrails · lean mass, recovery, HRV/RHR, sleep, weekly volume per muscle, e1RM per lift · protein adherence from tapping the protein target · 30d/90d/6m/1y ranges | **done** |
| **5.12** | Saved meals: builder that persists as ingredients are added, each searched through the shared food search · label entry per serving or per 100 g · "My foods" filter · swipe-to-delete foods and meals from search | **done** |
| **5.13** | Multi-sport workouts: 40-activity taxonomy across 7 groups · finished watch workouts persisted with every metric HealthKit exposes (distance, HR avg/max/min, elevation, cadence, power, swim strokes, laps, source device) · idempotent import keyed on the source's own ID, skipping watch strength blocks that duplicate a logged gym session · Garmin `/workouts` enrichment for fields Apple Health drops · activity picker on "New workout" offering start-live or import-from-watch · GPS-tracked live cardio · cardio-only ACWR from TRIMP, reported separately from lifting | **done** |
| 6 | AI coaching assistant (on-device summarization + guidance over the estimates) | deferred — only after phases 1–5 are proven stable and consistent in real use |

Phase 1 intentionally implements the three domain engines early even though they
"belong" to phases 4–5: they are pure Swift, carry the app's scientific value, and
are unit-testable with zero simulator/HealthKit dependency. Building them first
locks the math down before UI is layered on top.

## File map (implemented)
```
project.yml                                  XcodeGen spec (.xcodeproj generated)
ios/SuperFit/SupportingFiles/Info.plist      usage strings, URL scheme, launch
ios/SuperFit/SupportingFiles/SuperFit.entitlements  HealthKit + CloudKit
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
Core/Recovery/CyclicalBaseline.swift          detects multi-week rhythms, levels baselines
Core/Sleep/SleepAnalytics.swift              debt, bedtime consistency, sleep→HRV impact
Core/Health/RecoveryDataSource.swift         provider-agnostic recovery metrics
Core/Health/GarminProvider.swift             Garmin via own backend (see GARMIN.md)
Core/Nutrition/NutrientProfile.swift         shared nutrient types
Core/Nutrition/OpenFoodFactsClient.swift     barcode + search, no key
Core/Nutrition/USDAClient.swift              FDC API search, user's own key
Core/Nutrition/Micronutrient.swift           14 micros/markers, units, floor vs ceiling
Core/Nutrition/NutrientTargets.swift         RDAs adjusted for sex/age/goal/training
Core/Nutrition/SupplementCatalog.swift       51 supplements w/ per-serving nutrients
Core/Nutrition/SupplementIntake.swift        resolves daily/one-off/skip into a day
Core/Nutrition/FoodResolver.swift            cache → USDA FDC → OFF, delete
Core/Nutrition/MealComposer.swift            meal totals, missing-ingredient handling
Core/Nutrition/BarcodeScanner.swift          AVFoundation scanner + sim fallback
Core/Training/TrainingAnalytics.swift        tension-weighted volume + e1RM progression
Core/Training/ExerciseLibrary.swift          56-exercise catalog w/ 1-5 tension scores
Core/Training/WorkoutActivity.swift          40 activities, metrics each one carries
Core/Training/WorkoutImporter.swift          idempotent import + strength de-duplication
Core/Training/CardioLoad.swift               TRIMP load + cardio-only ACWR
Core/Health/WorkoutActivity+HealthKit.swift  two-way HKWorkoutActivityType mapping
Core/Health/LocationTracker.swift            GPS distance for live outdoor sessions
Core/Services/WorkoutSyncService.swift       workouts into SwiftData, Garmin enrichment
Core/Health/WatchWorkoutMonitor.swift        live session mirroring + finished observer
Core/Services/SyncCoordinator.swift          HealthKit → SwiftData day-keyed upserts
Core/Services/AggregationService.swift       trend fill, TDEE records, recovery score
Core/UI/Units.swift                          metric/imperial + keyboard dismiss
Core/History/HistorySeries.swift             chart series, TDEE backfill, rolling means
Core/Account/AccountManager.swift            Sign in with Apple, credential in Keychain
Core/Account/DataArchive.swift               export/import, merge or replace
Features/Dashboard/DashboardView.swift       cards + settings gear + trends
Features/History/HistoryView.swift           every trend, 30d-1y ranges
Features/History/HistoryChart.swift          shared themed chart card
Features/History/ProteinAdherenceView.swift  daily protein vs target, hit rate
Features/Settings/SettingsView.swift         account/ToS placeholders, units, profile
Features/Settings/ConnectedServicesView.swift  Garmin link/unlink
Features/Settings/AccountView.swift          sign in/out, sync status, backup, erase
Features/Profile/ProfileView.swift           pushed from Settings
Features/Weight/WeightView.swift             entry + trend chart, unit-aware
Features/Sleep/SleepView.swift               duration, stages, consistency, HRV impact
Features/Nutrition/DiaryView.swift           meal sections, targets vs intake
Features/Nutrition/NutritionView.swift       macros + micros vs targets, 7-day average
Features/Nutrition/SupplementsView.swift     day's supplements, catalog picker, custom
Features/Nutrition/FoodPickerView.swift      shared search: filter, swipe delete, meals
Features/Nutrition/FoodSearchView.swift      log portion on top of the picker
Features/Nutrition/MealBuilderView.swift     build/edit/log a saved meal
Features/Nutrition/CustomFoodView.swift      custom foods w/ consistency check
Features/Training/TrainingView.swift         start/history, weekly volume, strength
Features/Training/ActiveWorkoutView.swift    set logging, RIR, rest timer, picker
Features/Training/ActivityPickerView.swift   activity picker, live vs import
Features/Training/LiveCardioView.swift       timed session w/ GPS distance and pace
Features/Training/WorkoutDetailView.swift    every metric a workout captured
SuperFitTests/MetabolismEngineTests.swift
SuperFitTests/RecoveryEngineTests.swift
SuperFitTests/NutritionClientTests.swift     fixture-based decode tests
SuperFitTests/TrainingAnalyticsTests.swift   volume + progression math
SuperFitTests/SleepAnalyticsTests.swift      debt, midnight-wrap consistency, impact
SuperFitTests/NutrientTargetsTests.swift     RDA values + training/goal adjustments
SuperFitTests/CyclicalBaselineTests.swift    detection gates, levelling, shrinkage
SuperFitTests/QARegressionTests.swift        review findings, pinned
SuperFitTests/SupplementTests.swift          daily/skip/stop logic, catalog integrity
SuperFitTests/ServingOptionTests.swift       portion/gram/ounce conversion
SuperFitTests/DataArchiveTests.swift         round trip, idempotent merge, erase
SuperFitTests/BodyCompositionTests.swift     Katch vs Mifflin selection + sensitivity
SuperFitTests/HistorySeriesTests.swift       backfill, rolling mean, edge-averaged change
SuperFitTests/MealComposerTests.swift        meal totals, deleted ingredients, label conversion
```
