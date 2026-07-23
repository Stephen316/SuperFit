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

## Nutrition — USDA FoodData Central (authoritative fallback)
- `GET https://api.nal.usda.gov/fdc/v1/foods/search?query=...&api_key=KEY`
- `GET https://api.nal.usda.gov/fdc/v1/food/{fdcId}?api_key=KEY`
- Requires a free API key. **Not** committed — injected via xcconfig / Keychain,
  read at runtime. Prefer `Foundation`-labeled entries (lab-analyzed).

Resolution order when logging: local cache → Open Food Facts (branded/barcode) →
USDA (generic whole foods). Every fetched item is cached as a `Food` row so repeat
logging is offline.

## Barcode scanning
`AVCaptureSession` + `VNBarcodeObservation` (Vision) for EAN-13/UPC-A → OFF lookup.
Camera use needs `NSCameraUsageDescription`.

## Networking hardening
- HTTPS only, ATS enforced.
- 10 s timeout, exponential-backoff retry (max 3) on 5xx.
- Response size cap and JSON schema validation before mapping.
- Per-host rate limiting; results cached to avoid re-hitting public endpoints.
- No secrets in source; USDA key from `Secrets.xcconfig` (git-ignored) or Keychain.
