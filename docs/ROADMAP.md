# SuperFit — Roadmap

| Phase | Scope | Status |
|---|---|---|
| **1** | App shell + tab nav · SwiftData store · HealthKit read layer · UserProfile · weight tracking + trend chart · **MetabolismEngine + MacroCalculator + RecoveryEngine** (pure, tested, validated) | **done** |
| **2** | Nutrition DB (OFF/USDA clients) · barcode scan · food logging diary · macro tracking vs targets · custom foods · day-complete flag | **done** |
| 3 | Workout tracking · exercises/sets/RPE · weekly volume per muscle · progressive overload | planned |
| 4 | Wire MetabolismEngine to live data · nightly aggregation job · adaptive target UI | planned |
| 5 | Recovery scoring surfaced on dashboard · readiness-based training recs | planned |
| 6 | AI coaching assistant (on-device summarization + guidance over the estimates) | planned |

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
Core/Metabolism/MetabolicRecordAssembler.swift  day-complete-aware engine input
Core/Recovery/RecoveryEngine.swift           readiness 0–100
Core/Nutrition/NutrientProfile.swift         shared nutrient types
Core/Nutrition/OpenFoodFactsClient.swift     barcode + search, no key
Core/Nutrition/USDAClient.swift              FDC search, key via xcconfig
Core/Nutrition/FoodResolver.swift            cache → OFF → USDA, offline caching
Core/Nutrition/BarcodeScanner.swift          AVFoundation scanner + sim fallback
Features/Dashboard/DashboardView.swift
Features/Profile/ProfileView.swift
Features/Weight/WeightView.swift             entry + trend chart
Features/Nutrition/DiaryView.swift           meal sections, targets, complete toggle
Features/Nutrition/FoodSearchView.swift      search / scan / log portion
Features/Nutrition/CustomFoodView.swift      custom foods w/ consistency check
SuperFitTests/MetabolismEngineTests.swift
SuperFitTests/RecoveryEngineTests.swift
SuperFitTests/NutritionClientTests.swift     fixture-based decode tests
```
