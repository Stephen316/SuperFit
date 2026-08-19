# SuperFit — Data Model

Persistence: **SwiftData** (`@Model` classes) backed by a local SQLite store.
CloudKit support is gated behind the `SUPERFIT_CLOUDKIT` build condition because
the current personal-team build has no iCloud entitlement.

CloudKit compatibility shapes the schema: every relationship is **optional**, every
non-optional scalar has a **default**, and there are **no unique constraints**
(CloudKit doesn't enforce them — we dedupe in code by a `remoteID`/natural key).

## Entities

### UserProfile
Single row. Static-ish user facts + current goal.

| field | type | notes |
|---|---|---|
| id | UUID | |
| birthDate | Date | for age → BMR prior |
| biologicalSex | enum | male/female/other |
| heightCm | Double | |
| goal | enum | fatLoss, maintenance, muscleGain, recomposition |
| activityBaseline | enum | sedentary…athlete (prior only) |
| proteinPerKg | Double | override; default set by goal |
| unitSystem | enum | metric/imperial (display only; storage is metric) |

### BodyMetrics
One per day (the *smoothed* trend point). Raw weigh-ins can be many per day; we
keep raw samples too but the engine consumes the daily trend.

| field | type | notes |
|---|---|---|
| date | Date | day-granular key |
| weightKg | Double | raw entry or HealthKit sample |
| trendWeightKg | Double? | EWMA-smoothed, filled by aggregator |
| bodyFatPct | Double? | optional |
| leanMassKg | Double? | optional; preferred for protein if present |
| source | enum | manual, healthKit |

### DailyEnergy
Rolled-up activity for a day (from HealthKit).

| field | type |
|---|---|
| date | Date |
| activeEnergyKcal | Double |
| basalEnergyKcal | Double |
| steps | Int |
| distanceKm | Double |
| flightsClimbed | Int |

### NutritionLog  (a logged eating event)
| field | type | notes |
|---|---|---|
| date | Date | day key |
| loggedAt | Date | timestamp |
| foodID | UUID? | ref to Food (nullable for quick-add) |
| servingGrams | Double | |
| kcal, proteinG, carbsG, fatG, fibreG | Double | resolved at log time (immutable snapshot) |
| meal | enum | breakfast/lunch/dinner/snack |

Snapshotting macros at log time means editing a Food later never rewrites history.

### Food
Canonical food item (from OFF/USDA or custom).

| field | type | notes |
|---|---|---|
| id | UUID | |
| source | enum | openFoodFacts, usda, custom |
| remoteID | String? | barcode or FDC id — dedupe key |
| name, brand | String | |
| per100g: kcal, proteinG, carbsG, fatG, fibreG | Double | canonical basis |
| micros | [String: Double] | JSON blob, per 100g |
| isFavorite | Bool | |

Derived views: **SavedMeal** (named list of NutritionLog templates) and **Recipe**
(list of Food + grams → computed per-serving macros). Both reference Food; recipes
store a materialized per-serving snapshot for fast logging.

### Workout / Exercise / SetEntry
| Exercise | | |
|---|---|---|
| id | UUID | |
| name | String | |
| primaryMuscle | enum | chest, back, quads, hamstrings, glutes, shoulders, biceps, triceps, calves, core |
| secondaryMuscles | [enum] | fractional volume |
| category | enum | barbell, dumbbell, machine, cable, bodyweight |

| TrainingSession | | |
|---|---|---|
| id | UUID | |
| startedAt / endedAt | Date | |
| templateName | String? | e.g. "Push A" |
| bodyMetricSnapshotKg | Double? | for load-relative strength |

| SetEntry | | |
|---|---|---|
| session | ref | |
| exercise | ref | |
| order | Int | |
| weightKg | Double | |
| reps | Int | |
| rir | Int? | reps-in-reserve (or RPE derived) |
| isWarmup | Bool | excluded from working volume |

`MuscleGroupVolume` is **derived**, not stored: aggregated per ISO week from
SetEntry via `VolumeAggregator` (working sets, weighted by primary=1.0 /
secondary=0.5).

### SleepData
| field | type |
|---|---|
| date | Date (the wake day) |
| inBedMinutes | Int |
| asleepMinutes | Int |
| deepMinutes, remMinutes, coreMinutes | Int |
| efficiency | Double (asleep/inBed) |

### RecoveryScore (derived, not synced)
| date | Double score 0–100 | components: sleepScore, hrvScore, rhrScore, loadScore | recommendation enum |

### MetabolicEstimate (derived, not synced)
| date | tdeeKcal | window enum (d7/d14/d30) | confidence 0–1 | trendSlopeKgPerWeek | avgIntakeKcal |

### MacroTargets (derived, cached)
| date | kcal | proteinG | fatG | carbG | goal |

## Indexing & query patterns
- Screens and sync services use date predicates and fetch limits so only their
  visible or computational window is materialised in memory.
- The deployment target is iOS 17; SwiftData's `#Index` macro is iOS 18-only, so
  the current schema declares no explicit model indexes. SQLite may still scan
  to satisfy a bounded predicate, but the app no longer decodes an unlimited
  result set. Add date/session indexes when the minimum OS moves to iOS 18.

## Privacy at rest
- The SwiftData store lives in the app container and uses iOS data protection.
- A user can explicitly upload a full encrypted-in-transit archive to their
  authenticated Supabase account for backup. No analytics SDK receives health
  values.
