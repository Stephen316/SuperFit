# SuperFit — Algorithm Logic

The three engines below are pure functions. Constants are grouped so they can be
tuned against real user cohorts later.

## Validation against published references (28/28 pass)
- **Mifflin-St Jeor prior** — exact vs the published equation; moderate-PAL
  output inside the DLW population range.
- **Epley e1RM vs NSCA %1RM table** — within 2.5 pp at every rep count 1–10.
  Found+fixed: Epley overpredicts singles by 3.3%; a 1-rep set now counts as its
  own 1RM.
- **DLW-style TDEE recovery** — 100 simulations, σ=0.6 kg daily scale noise:
  mean bias +0.5 kcal, mean abs error 79 kcal, 95th-percentile 179 kcal.
- **Adaptive thermogenesis (Hall-model −27 kcal/day per kg lost)** — 12-week
  cut: the 30-day estimate tracks the declining true TDEE within ~26 kcal.
- **Tissue energy density** — if 25% of loss is lean tissue (Hall 2008 bounds),
  the 7700 kcal/kg assumption biases TDEE ~118 kcal high; acceptable, and it
  shrinks as high protein + training preserve lean mass.
- **Consistent under-reporting (Lichtman 1992)** — a 15% logging bias
  self-corrects: a target set from the biased TDEE still lands within ~35 kcal
  of the intended physiological deficit while the bias stays consistent.
- **Protein/fat grid** — never below Morton 2018's 1.6 g/kg protein or AMDR 20%
  fat at any goal × bodyweight × calorie combination.
- **Loss-rate clamp** — engages at exactly 1.0 %BW/week (Garthe 2011 supports
  <1%/wk for lean-mass retention). ACWR bands match Gabbett 2016.

---

## 1. Metabolism Engine (adaptive TDEE)

### Principle
Conservation of energy over a window:

```
TDEE ≈ average_daily_intake  −  daily_energy_stored_as_tissue
```

Tissue energy uses the standard **7700 kcal per kg** of body-mass change.

```
energyFromWeightChange (kcal/day) = trendSlope(kg/day) × 7700
TDEE = avgIntake − energyFromWeightChange
```

Sign check:
- Weight **stable** (slope 0): `TDEE = avgIntake`. Intake 2600 → TDEE 2600. ✓
- Losing **0.5 kg/week** = −0.0714 kg/day → energyFromWeightChange = −550.
  `TDEE = 2600 − (−550) = 3150`. So a 2600-kcal intake represents a **~550
  kcal/day deficit** against a 3150 TDEE. ✓ (matches the brief's example)

### Why not BMR equations or watch calories?
BMR formulas have ±15–20% individual error; wrist active-energy is worse and its
error is goal-correlated. The trend method measures *your* actual expenditure from
the only ground truth that matters — what the scale does given what you ate.

### Steps
1. **Display trend** — exponentially weighted moving average over daily weight
   means: `trend[t] = α·weight[t] + (1−α)·trend[t−1]`, `α = 2/(N+1)`, N≈10. This
   is the smooth line the user sees. It is **never** fed to the slope estimator —
   validation showed EWMA lag biases an OLS-on-smoothed slope ~11% low over 30
   days and ~30% low over 14 days, which propagates directly into TDEE.
2. **Trend slope** — **Theil–Sen estimator** (median of all pairwise slopes) over
   the *raw* daily means. Validated properties: exact on clean trends at both 14-
   and 30-day windows; a single +2 kg water/glycogen spike anywhere in the window
   (including the endpoints, where OLS leverage is worst) moves the slope by ~0;
   noise performance identical to OLS (mean abs error 0.098 vs 0.100 kg/wk over
   50 trials of σ=0.7 kg daily noise). n ≤ 30 points → ≤ 435 pairs, negligible.
   Units: kg/day → ×7 for kg/week display.
3. **Average intake** — mean of logged daily kcal over the window, **only over days
   with logging**. Coverage = loggedDays / windowDays.
4. **Raw TDEE** = avgIntake − slope×7700.
5. **Blend with prior** when data is thin. The prior separates passive from
   active energy: once ≥7 days of HealthKit activity have synced,
   `prior = (Mifflin-St Jeor BMR + mean daily active energy) / 0.9` (the ÷0.9
   grosses up for the ~10% thermic effect of food) and the self-reported
   activity factor is ignored. Before that, the coarse fallback
   `prior = BMR × activity factor` applies. Watch active-energy error stays
   quarantined inside the prior — it never touches the measured trend TDEE,
   which overrides the prior as confidence grows. Confidence-weighted:
   ```
   w = coverage × min(1, windowDays/14) × min(1, weighIns/ (windowDays/3))
   TDEE = w·rawTDEE + (1−w)·prior
   confidence = w
   ```
   New users lean on the equation; after ~2–3 weeks of data the measured value
   dominates and the equation is effectively discarded.
6. **Multi-window output** — compute for 7/14/30 days. The 30-day is the headline
   TDEE (most stable); the 7-day flags fast metabolic shifts (adaptive
   thermogenesis during a long cut).

### Basal rate

**Katch-McArdle when lean mass is known** — `370 + 21.6 x LBM`. It drops sex, age
and height, because lean mass already carries what those were proxying for.
**Mifflin-St Jeor otherwise.**

Lean mass comes from Apple Health (smart scales write body fat and lean mass
alongside weight) or from a measured body-fat figure entered in Profile.

The accuracy gain is real but entirely hostage to the input, since 5 percentage
points of body-fat error moves basal by ~89 kcal:

| Body-fat source | Input error | Basal error |
|---|---|---|
| None — Mifflin-St Jeor | — | ±180 kcal |
| DEXA | ±1.5% | ±27 kcal |
| BodPod | ±2.5% | ±44 kcal |
| Smart scale (BIA) | ±6% | ±106 kcal |
| Self-estimated bracket | ±7.5% | ±133 kcal |

**Self-estimated ranges are deliberately not offered.** A bracket lands at ±133
against Mifflin's ±180 — barely better, and the error isn't random: people
systematically underestimate their own body fat, which inflates lean mass,
inflates basal, and raises the calorie floor enough to block a legitimate
deficit. Unbiased noise beats biased noise, so the field accepts a single
measured number or nothing.

The prior is blended out within 2–3 weeks as measured TDEE gains confidence, so
this mainly affects the first fortnight and the permanent BMR floor on calorie
targets.

### Confidence

`confidence = coverage x dataMaturity x weighInDensity`, clamped to 0-1.

No day of the week is treated specially. All days are assumed exchangeable for
intake and training, so *which* days are missing never changes the estimate --
only how many.

### Imputing unlogged days

The energy-balance identity differences average intake against the weight slope,
but the slope spans every day in the window while logged intake covers only some.
Unlogged days are therefore filled in from the intake trend rather than dropped:

```
slope, intercept = Theil-Sen fit over logged daily intake
imputed(day)     = clamp(intercept + slope x day, observedMin ... observedMax)
avgIntake        = mean over all window days (observed + imputed)
```

Under exchangeability the mean of logged days is already unbiased, and flat
mean-imputation would return the same number. What this adds is **time**: when
intake drifts across the window *and* the gaps cluster in time -- an unlogged
first week, say -- the flat average describes the wrong part of the window. That
matters here because the app moves the calorie target as TDEE shifts, so drifting
intake is the normal case, not the exception.

Two guards keep the fit honest:

- **Significance.** The drift across the window must exceed one residual standard
  deviation, otherwise the flat mean is used. Fitting noise and extrapolating it
  is worse than not trying.
- **Extrapolation.** Imputed values are clamped to the observed min/max, so a long
  unlogged stretch cannot run the line away to implausible numbers.

Mean absolute error against true window intake, 300 simulated windows of 30 days,
8 days unlogged, sigma = 180 kcal:

| Intake pattern | Gaps | Logged-days mean | Imputed |
|---|---|---|---|
| Flat | random | 14.6 | 15.3 |
| Flat | clustered | 14.5 | 20.5 |
| Rising 600 kcal/30 d | random | 22.9 | 16.7 |
| Rising 600 kcal/30 d | clustered | 70.9 | 25.3 |
| Falling 600 kcal/30 d | clustered | 69.1 | 25.3 |

The trade is deliberate: about 6 kcal worse when intake is genuinely flat and the
gaps happen to cluster, against 45 kcal better whenever intake is actually moving.

Coverage still discounts confidence -- imputed days are inference, not
measurement, and a mostly-imputed window deserves less weight against the prior
even though the imputation itself is unbiased.

### Calorie-target guardrails

Weekly change is capped at 1% of bodyweight lost / 0.5% gained, **and the target
never falls below basal metabolic rate** (`TDEEEstimate.basalKcal`, persisted so
it survives relaunch; falls back to 1200 kcal on pre-migration rows). The relative
guardrail alone is a fraction of *bodyweight*, not of metabolic rate, so it can
prescribe sub-basal intake to a small or low-TDEE user — the point at which
lean-mass loss and adaptive suppression stop being avoidable.

### Known limitation: under-reporting

Imputation fixes *missing* days. It cannot fix days that were logged
inaccurately: if a portion goes unrecorded or is underestimated, the logged value
is wrong rather than absent, and no amount of interpolation recovers it.

A **consistent** bias largely cancels. Validation against Lichtman (1992) shows a
15% systematic under-report still lands a target within ~35 kcal of the intended
physiological deficit, because the same bias sits on both sides of the
adjustment: TDEE reads low, and so does the target derived from it.

An **inconsistent** bias does not cancel -- logging carefully on ordinary days and
loosely on unusual ones biases the average downward with nothing to detect it
from. This is inherent to any diary-based system.

Two guards limit the damage:

- Days finalize automatically at midnight; today never counts toward the estimate
  while it is still being logged.
- A past day counts only if at least 800 kcal was recorded
  (`MetabolicRecordAssembler.minPlausibleIntake`), which filters abandoned
  logging days -- breakfast entered, then nothing -- that would otherwise be
  treated as a genuine low-intake day and drag TDEE down.

### Adaptive target adjustment
Given goal + current TDEE:
```
fatLoss:        target = TDEE × (1 − 0.20)     // ~0.5–0.7 kg/wk
recomposition:  target = TDEE × (1 − 0.10)     // small deficit, 5–15% band
maintenance:    target = TDEE
muscleGain:     target = TDEE × (1 + 0.10)     // lean bulk
```
Targets are re-clamped so weekly loss never exceeds **1%** of bodyweight (muscle-
retention guardrail) and gain never exceeds **0.5%/week** (limits fat gain).

---

## 2. Macro Calculator

Order: protein → fat floor → carbs fill remainder.

```
proteinG = proteinPerKg × mass          // mass = leanMass if known else bodyweight
                                         // recomp/cut default 2.0 g/kg (band 1.6–2.2)
fatG     = max(0.8 × bodyweightKg,       // hormonal health floor
               0.25 × kcal / 9)
carbG    = max(0, (kcal − 4·proteinG − 9·fatG) / 4)
```
If protein+fat floors exceed target kcal (aggressive cut), carbs go to a 50 g
minimum and the deficit is reported as protein-driven, not carb-starved.

---

### Reconciliation

Protein and the fat floor are set first, then carbs take the remainder. When that
remainder falls under the 50 g carb floor the split would otherwise overspend the
calorie target — 120 kg cutting at 1760 kcal produced 2024 kcal of macros — so the
calculator trims back in priority order: **fat down to 0.5 g/kg** (essential-fat
floor), then **protein down to 1.2 g/kg**, protein last because it is the macro
most worth defending in a deficit. `MacroTargets.macroKcal` exposes the total for
assertion; it matches `kcal` to within rounding across the whole plausible input
grid. Targets below the sum of the floors can't be balanced at all, and are
prevented upstream by the BMR floor.

### Protein basis

The literature's 1.8–2.2 g/kg figures are referenced to **bodyweight**. Applying
them to lean mass under-prescribes by the body-fat fraction (82 kg at 65 kg LBM →
130 g instead of 164 g), so the lean-mass basis carries its own higher values —
2.4 g/kg cutting, 2.2 g/kg otherwise (Helms et al. 2014 give 2.3–3.1 g/kg LBM;
the top of that range is contest prep, so this stays conservative).

## 3. Recovery Engine (readiness 0–100)

Weighted composite of four normalized sub-scores. Each metric is scored against the
user's **own rolling baseline** (60-day mean/SD), not population norms.

| component | weight | scoring |
|---|---|---|
| Sleep | 0.35 | duration vs 8 h need + efficiency; piecewise-linear |
| HRV | 0.30 | z-score vs baseline; above baseline = good, capped |
| Resting HR | 0.20 | inverse z-score; elevated RHR = suppressed recovery |
| Training load | 0.15 | acute:chronic workload ratio (ACWR), penalize >1.5 |

```
score = 100 × (0.35·sleep + 0.30·hrv + 0.20·rhr + 0.15·load)
```

**ACWR** = (7-day training volume) / (28-day average 7-day volume). ~0.8–1.3 is the
"sweet spot"; >1.5 spikes injury risk → load sub-score drops.

### Recommendation bands
```
90–100 : Push intensity — add load or a top set
70–89  : Normal training
50–69  : Reduce volume ~30%, keep intensity
<50    : Recovery focus — mobility / zone-2 / rest
```

The recommendation is banded on the **rounded** score, not the raw one: 89.5
displays as 90, and a 90 shown beside "Normal training" contradicts the table above.

Sleep scores duration (70%) and efficiency (30%). Efficiency defaults to **0.9**
when unknown — phone-only tracking reports duration but not time in bed — so the
missing component neither rewards nor punishes. It must reach the engine as `nil`,
never 0: `SleepData.efficiency` is optional for exactly this reason, since a false
zero reads as "awake all night" and strips 30% off the component.

Training load counts bodyweight work. Tonnage is `(externalLoad + bodyweight ×
bodyweightFraction) × reps`; without the second term a calisthenics session scores
zero load and ACWR reports the athlete as fully rested.

### Cyclical baselines

HRV and resting heart rate are z-scored against a flat 60-day mean and SD. For
anyone with a genuine multi-week physiological rhythm -- most obviously the
menstrual cycle, where HRV falls and resting HR rises 2-5 bpm through the luteal
phase -- that flat baseline does two harmful things. It inflates the SD, blunting
real signal all month; and it pushes one phase systematically negative, so the app
recommends reducing volume on schedule every month for no physiological reason.
Acting on that advice means cutting training every cycle without cause.

`CyclicalBaseline` finds the rhythm in the marker data itself, so it needs nothing
extra from the user and works for people who don't log periods. It detects only
that a marker repeats on a 21-35 day period; nothing identifies what the rhythm
is.

**Method.** Robustly detrend (Theil-Sen, so months of rising fitness don't read as
rhythm), then for each candidate period fold the series onto one cycle, take the
median at each phase position, and smooth circularly. The winning period is the
one whose profile explains the most variance (adjusted R², since a longer period
fits more freely and would otherwise always win).

Period selection by *variance explained* rather than autocorrelation peak matters
more than it sounds: on realistic noise the autocorrelation peak recovered the
true period 0% of the time -- a 28-day cycle read as 25 -- while this recovers it
exactly on 82-99% of windows of six or more cycles. A period off by even one day
drifts a day out of phase per cycle, so a wrong period makes the correction worse
than none.

**Evidence bar before anything is adjusted:**

| Gate | Value |
|---|---|
| Complete cycles observed | >= 3 |
| Span of history | >= 90 days |
| Adjusted R² of the profile | >= 0.10 |
| Amplitude vs residual SD | >= 0.33 |
| Every phase position | >= 2 observations |

Measured false-positive rate on rhythm-free data -- flat, drifting, and
weak-signal (2-3 ms in 6 ms noise): **0%**.

**Correction is shrunk toward zero** until enough cycles are in:
`confidence = min(1, cyclesObserved / 6)`. Three cycles applies half the offset,
six or more applies all of it. Simulation showed partial correction beating full
at short windows and matching it once six cycles are in -- a confidently
misaligned correction is worse than a timid one.

Residual cyclical error on the most recent 28 days, where accumulated phase drift
is worst (true 28-day rhythm, 9 ms amplitude, 6 ms nightly noise):

| History | Detects | Uncorrected | Corrected |
|---|---|---|---|
| 120 d | 88% | 2.85 ms | 1.50 ms |
| 180 d | 92% | 2.85 ms | 1.35 ms |
| 240 d | 98% | 2.85 ms | 1.16 ms |
| 300 d | 99% | 2.85 ms | 0.86 ms |

Both the day's reading *and* the baseline it is compared against are levelled by
the same profile. Correcting only one side would shift the reading against an
uncorrected baseline and invert the error being fixed.

**Application is gated on a female profile** by product decision. The detector
itself is blind -- a 21-35 day rhythm could appear in anyone's data from shift
work or training blocks -- so restricting the correction avoids reshaping
baselines on a coincidence where no such physiology is expected. `.other` is
excluded: it carries no information either way, and silently altering someone's
recovery scores on an assumption is worse than leaving them alone.

Detection results persist to `CyclicalPatternRecord` (on-device, like all health
data) so the inference is inspectable rather than invisible. A pattern that stops
qualifying is marked inactive rather than deleted, so one that comes and goes is
visible instead of silently churning.

Missing inputs degrade gracefully: a component with no data is dropped and the
remaining weights renormalize, with a `dataCompleteness` flag surfaced in the UI so
the user knows the score is partial.

## 4. Sleep Analytics

Sleep is stored per wake-day with duration, stages, and — from `SleepSampleBuilder`
— the clock bounds of the *asleep* segments. In-bed bounds are deliberately not
used for bedtime: they include lying awake reading, which blurs the consistency
signal.

- **Debt** is one-directional: `Σ max(0, need − asleep)`. A long Sunday cannot
  repay a short Monday, because sleep loss is not a bank balance.
- **Consistency** is the SD of bedtime, with times mapped onto an axis centred on
  midnight (evening times become negative) so 23:50 and 00:10 read as 20 minutes
  apart rather than 23 hours. Reported only with ≥3 known bedtimes.
- **Sleep → HRV impact** splits nights at 7 h 30 m and compares mean next-morning
  HRV. Withheld below 4 nights per side, where one outlier would dominate.
  Correlational, and labelled as such in the UI.

## 5. Nutrient Targets

Macros come from §2. Micronutrient targets start from published reference intakes
(NIH ODS adult RDAs; WHO/US Dietary Guidelines for the ceilings) and adjust for the
demands training actually creates:

| Adjustment | Trigger | Rationale |
|---|---|---|
| Sodium 2300 → 3000 mg | ≥3 sessions/wk | Sweat loses ~1 g Na/L; the sedentary ceiling under-serves athletes |
| Potassium +15% | ≥3 sessions/wk | Sweat losses; commonly under-consumed |
| Iron +30% | ≥3 sessions/wk | Foot-strike haemolysis and sweat losses |
| Calcium 1000 → 1200 mg | fat-loss goal | Bone-turnover risk rises in a deficit |
| Iron 8 → 18 mg | female, ≤50 | Menstrual losses |
| Calcium → 1200 mg, vitamin D → 20 µg | age >50 | Absorption declines |

Ceilings (saturated fat, sugar) are proportions of energy — 10% each — so they
scale with the calorie target rather than sitting at a fixed gram figure.

**Coverage caveat:** ~87–98% of bundled FDC foods carry each micronutrient, but
custom foods and most branded (OFF) items carry macros only. The UI reports the
share of logged energy backed by full nutrient data, because otherwise a day of
branded food reads as a deficiency. Micronutrient intake is also genuinely spiky —
one portion of liver covers a week of vitamin A — so a 7-day average view is
offered and is the more honest read.
