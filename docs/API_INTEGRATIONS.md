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
- Search: `GET https://search.openfoodfacts.org/search?q=…&page=…&page_size=25`
- No key. Set a descriptive `User-Agent: SuperFit/1.0 (contact@…)` per their policy.
- Map `nutriments` (per 100 g) → `Food.per100g`. Coverage is crowd-sourced; treat
  missing fields as nil, not zero.

**Why not `cgi/search.pl`.** That endpoint is deprecated and unreliable in
practice — probing it returned 503 on two of three consecutive attempts while the
current search service answered every time. It remains wired as a fallback for
when the new service is down, but it is no longer the primary.

The two return different shapes for one field: `brands` is an **array** on the
search service and a comma-joined **string** on the legacy endpoint and the
product endpoint. `OFFNutriments` is shared; the containers are not.

**Store filtering is own-brand only.** `brands_tags` finds a retailer's own range
(Tesco Finest, Lidl Deluxe). The `stores_tags` field — where a product was *seen*
— returns **0 results for every retailer tested**, so "sold at Tesco" is not
possible and the UI says "own brand" rather than implying it.

Tag spellings are Open Food Facts', not the shop name: `sainsbury` returns 141
products against `sainsbury-s`'s 3,345. Every tag in `StoreBrand` was checked
against a live count. Coverage is uneven — Lidl/Aldi/Carrefour hit the 10,000
result cap, Tesco 8,844, SuperValu 764, Dunnes 90 — and many own-brand fresh items
(whole chicken, loose produce) carry no energy value and are dropped before
reaching the picker.

A store filter queries Open Food Facts alone: USDA has no supermarket own-brand
ranges outside the US and no tag to filter on, so including it would only dilute
the results. Country sorting is skipped too — Tesco's own brand is British by
definition, so the second request buys nothing.

**Country sorting, not filtering — in three tiers.** Results merge from three
concurrent queries, duplicates dropped, in precision order:

1. the chosen country's `countries_tags`
2. market-adjacent countries, OR'd into a single request
3. unrestricted

Unweighted, a UK search for "chicken breast" returns a Spanish product above
Tesco's; weighted, the top three are Tesco, Sainsbury's and Morrisons. A hard
filter was rejected because it hides imported or holiday purchases with no signal
the product exists at all.

The neighbour tier matters most where a country's own coverage is thin. Measured:
"milk" restricted to Ireland returns **2,125** products; the UK tier behind it adds
**7,021**. Without it an Irish user sees a fraction of what's on their shelves,
because the same chains span both. Adjacency means "realistically the same
shelves", not a shared border.

Several tags OR into one request rather than one per country — verified live, a
5-way OR for Germany's neighbours returns results normally. A country with no
listed neighbours costs two requests, not three.

**Region selection.** `Settings → Food database` sets the country; the default
follows `Locale.current.region` and names what it resolved to, so the choice isn't
blind. An explicit setting wins, and an unknown stored code falls back to the
device rather than leaving search silently unweighted. It also drives which
retailers the store chips offer, so both move together.

Not GPS, deliberately: a location prompt on the food tab reads as invasive for a
grocery search, it needs a signal, and it breaks the moment you travel — your
cupboard doesn't change nationality because you're abroad for a week. The region
*setting* is the better signal for "whose products am I eating", which is the
actual question. Tags are English lowercase names (`united-kingdom`), not ISO
codes; unmapped regions search unweighted rather than sending a tag matching
nothing.

## Nutrition — USDA FoodData Central API
- Search: `GET https://api.nal.usda.gov/fdc/v1/foods/search?query=…&api_key=…`
- Detail: `GET https://api.nal.usda.gov/fdc/v1/food/{fdcId}?api_key=…` — the only
  source of `foodPortions`, so it's fetched lazily when the log sheet opens
  rather than once per search result.
- `dataType=Foundation,SR Legacy,Branded` in the main request — lab-analyzed
  generics plus USDA's branded set, all carrying full micronutrient data.
- `Survey (FNDDS)` is requested **separately**, never in the same call. It adds
  foods *as eaten* ("dirty rice", "rice pilaf", "chicken curry, restaurant") where
  the other three carry ingredients.

  Putting it in the main request makes that request fail intermittently. Measured
  over repeated identical calls: the three stable types returned 200 **12/12**,
  adding the survey type dropped to **5/12**, the rest 400s from USDA's edge
  (nginx HTML body, not an API error). No encoding of the space and parentheses
  helped — `%20`+`%28%29` gave 5/10, literal parens 7/10, `+` for space 4/10 — so
  the value itself is what trips it, not the escaping.

  It therefore runs as an independent, retried, non-throwing request whose results
  are appended: **11/12 availability at three attempts**, and a failure can never
  turn a working search into an empty one.
- `pageNumber` drives pagination. USDA reports no page count, so "another page may
  exist" is inferred from a full page of results.
- Nutrient ids are the 1000-series (1008 kcal, 1003 protein, 1089 iron, …);
  `USDAClient.microIDs` maps them to `Micronutrient`.
- Entries with no energy value are dropped: a food that logs as 0 kcal is worse
  than one that isn't offered.

**Key handling.** Free key from <https://fdc.nal.usda.gov/api-key-signup.html>,
entered in Settings → Connected services and stored in the **Keychain**. Rate
limit is 1,000 requests/hour per key, which one user's searching will not
approach.

A key may also be injected at build time via `USDA_API_KEY` in the gitignored
`Secrets.xcconfig`, substituted into Info.plist and read as a **fallback** when
the Keychain is empty. The Keychain always wins, so pasting a key in Settings
overrides the build.

This exists because Keychain entries don't survive a reinstall without iCloud
Keychain — unavailable on a personal Apple team, which also can't hold a
provisioning profile longer than 7 days, so reinstalls are frequent. Without it
the key has to be re-pasted every few days.

The trade is explicit: an injected key reaches the app bundle and can be
recovered from it. That is acceptable for a personal build of a free,
per-key-rate-limited, revocable key. **A build given to anyone else should leave
the setting unset** and rely on the settings screen. The key is never committed —
`Secrets.xcconfig` is gitignored and `Secrets.example.xcconfig` ships blank.

**Serving sizes.** `foodPortions` gives household measures — "1 medium" at 118 g,
"1 cup, sliced" at 150 g — which is how people actually think about food. USDA
splits each across `amount`, `measureUnit.name` and `modifier` with inconsistent
population (`measureUnit` is often the literal string "undetermined"), so labels
are assembled in preference order and anything without a usable gram weight is
dropped. Branded items carry no `foodPortions` but do have
`householdServingFullText` alongside `servingSize`, which is used instead.

Portions are cached on the `Food` row, so a food logged once keeps its serving
options offline and costs no second request. The log sheet then offers portions
first, then grams and ounces — always both, so nothing is unloggable when a
source has no portion data. Ounces use the international avoirdupois definition
(28.349523125 g).

**Resolution order:** local cache → USDA FDC → Open Food Facts. The two network
sources run concurrently, and either failing leaves the other's results intact.

**Ranking is by product locality, not by source.** `FoodRelevance` bands every
result and sorts:

| Band | What it is |
|---|---|
| 1 | Your own foods — logged before, or custom |
| 2 | Generic whole foods — no supplier, so no country |
| 3 | Sold in your country |
| 4 | Sold in a neighbouring country |
| 5 | Everything else |

The sources have no standing of their own. USDA happens to hold the lab generics
and Open Food Facts happens to hold British supermarket own-brands; that's an
accident of who catalogued what and says nothing about which result the user
wants. Concatenating source-by-source put **up to 50 USDA entries, mostly US
branded, above every Tesco product** for a UK user — the results were there,
just unreachable.

Generic whole foods rank above **every** branded product, including the local
shelf. Two reasons: most logging is of ingredients rather than specific packets,
and the generic entries are the better data — Foundation and SR Legacy are
lab-analysed with full micronutrient profiles, where a crowd-sourced branded entry
often carries macros alone. The country bands exist for when you do want the
specific packet.

The generic check runs *before* the country bands, so a generic that a source
happens to tag with a country isn't pulled down into a retail band by it.

Provenance comes from Open Food Facts `countries_tags` (verified present on 10/10
live hits, stripped of the `en:` prefix) and, for USDA, `dataType` for generic
versus branded plus `marketCountry` mapped onto the same tag vocabulary. An absent
market leaves a food unattributed rather than asserting a country it never
claimed — unattributed can't be ranked local, but isn't assumed foreign either.

The sort carries an explicit position tiebreak rather than relying on
`sorted(by:)`, which Swift does not document as stable: without it, identical
searches would reshuffle.

**Request cost and debounce.** One completed search is **5–7 HTTP requests**: USDA's
stable datatypes (1), the survey dataset with its retries (1–3), and three Open
Food Facts country tiers (3).

Typing fires a task per keystroke, but each cancels the previous and waits before
touching the network, so a normal word costs one search rather than one per letter.
The wait is **600 ms**, raised from 400: at 400 an ordinary mid-word pause fired its
own search, so one word could cost three of the above — 15–21 requests.

The minimum query is **3 characters**, from `FoodSearch.minimumQueryLength`. A
two-letter term almost never means what the user intended and cost a full search.
The constant is shared because the guard appears in the resolver, both clients and
the empty-state text — four copies that would otherwise drift and let a query reach
one source but not another. A store chip is exempt: browsing a retailer's range is
a legitimate search with no term at all.

**Pagination.** "Load more" appends the next page from both sources, deduplicated
against what's already shown. Cached rows and supplements appear on page 1 only —
they're already complete, and repeating them would push the remote results the
user is paging *for* further down each time. It's a button rather than infinite
scroll: each page costs three network calls, and past the first 25 the results are
rarely what was wanted, so paging should be a decision rather than a side effect
of scrolling.

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
