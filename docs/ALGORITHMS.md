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

### Known limitation: partial-day logging bias
If a user logs weekdays but not weekends *and* eats more on unlogged days, the
average intake — and therefore TDEE — is biased low (validation: 2600 logged
weekdays / 3650 unlogged weekends / stable weight → estimated 2642 vs true 2900,
−258 kcal). Coverage lowers confidence but cannot detect the asymmetry. Phase 2
mitigation: a per-day "logging complete" flag; only complete days enter the
intake average, matching MacroFactor's approach.

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

Missing inputs degrade gracefully: a component with no data is dropped and the
remaining weights renormalize, with a `dataCompleteness` flag surfaced in the UI so
the user knows the score is partial.
