# SuperFit — External Integrations

## HealthKit (read-only)
Requested types (least-privilege — read only, no writes in Phase 1):

- Activity: `activeEnergyBurned`, `basalEnergyBurned`, `stepCount`,
  `distanceWalkingRunning`, `flightsClimbed`
- Body: `bodyMass`, `bodyFatPercentage`, `leanBodyMass`
- Workouts: `HKWorkoutType` + per-workout `heartRate`, `activeEnergyBurned`
- Sleep: `sleepAnalysis` (stages on supported devices)
- Heart: `restingHeartRate`, `heartRateVariabilitySDNN`, `vo2Max`

Patterns:
- `HKSampleQuery` for backfill on first launch (365-day history).
- `HKObserverQuery` + `enableBackgroundDelivery` for incremental updates.
- `HKStatisticsCollectionQuery` for daily-bucketed activity sums.
- All access serialized through an `actor` (`HealthKitManager`).

`Info.plist` keys (required or the app is rejected):
- `NSHealthShareUsageDescription` — "SuperFit reads your weight, activity, sleep,
  and heart data to estimate your true energy expenditure and recovery. Your health
  data stays on your device and your private iCloud. It is never sold or shared."
- `NSHealthUpdateUsageDescription` — (only if/when we write workouts back)
- Capabilities: HealthKit, Background Modes → Background fetch, iCloud → CloudKit.

## Nutrition — Open Food Facts (barcode-first, free)
- Product by barcode: `GET https://world.openfoodfacts.org/api/v2/product/{barcode}.json`
- Search: `GET https://world.openfoodfacts.org/cgi/search.pl?search_terms=...&json=1`
- No key. Set a descriptive `User-Agent: SuperFit/1.0 (contact@…)` per their policy.
- Map `nutriments` (per 100 g) → `Food.per100g`. Coverage is crowd-sourced; treat
  missing fields as nil, not zero.

## Nutrition — USDA FoodData Central API
- Search: `GET https://api.nal.usda.gov/fdc/v1/foods/search?query=…&api_key=…`
- `dataType=Foundation,SR Legacy,Branded` — lab-analyzed generics plus USDA's
  branded set, all carrying full micronutrient data.
- Nutrient ids are the 1000-series (1008 kcal, 1003 protein, 1089 iron, …);
  `USDAClient.microIDs` maps them to `Micronutrient`.
- Entries with no energy value are dropped: a food that logs as 0 kcal is worse
  than one that isn't offered.

**Key handling.** Free key from <https://fdc.nal.usda.gov/api-key-signup.html>,
entered by the user in Settings → Connected services and stored in the
**Keychain**. It is never compiled into the binary — a bundled key ships to every
install and is trivially extracted from the app package. Rate limit is 1,000
requests/hour per key, which one user's searching will not approach.

**Resolution order:** local cache → USDA FDC → Open Food Facts. The two network
sources run concurrently, and either failing leaves the other's results intact.

**Offline behaviour.** Search needs a connection. Every fetched food is cached as
a `Food` row, so anything logged before — the long tail of what someone actually
eats — still resolves and re-logs offline. Barcode scanning and custom foods are
unaffected. With no key configured, search degrades to cache + Open Food Facts
rather than failing, and the UI says which case applies.

## Barcode scanning
`AVCaptureSession` + `VNBarcodeObservation` (Vision) for EAN-13/UPC-A → OFF lookup.
Camera use needs `NSCameraUsageDescription`.

## Networking hardening
- HTTPS only, ATS enforced.
- 10 s timeout, exponential-backoff retry (max 3) on 5xx.
- Response size cap and JSON schema validation before mapping.
- Per-host rate limiting; results cached to avoid re-hitting public endpoints.
- Zero API keys anywhere in the app.
