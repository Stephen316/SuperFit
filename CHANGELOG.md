# Changelog

Notable changes to SuperFit. Newest first.

The first entry below was reconstructed from git history and is therefore coarser
than later ones will be: it summarises 82 commits by theme rather than listing each
one. Entries from here on are written per merge by `/pr`, one line per change.

Nothing has shipped yet — `MARKETING_VERSION` stays at 1.0 until a release is cut.

## 1.0 (build 1) — 2026-08-13

### Added

- Multi-sport workouts, with Apple Watch and Garmin sync and live phone tracking
- Adaptive TDEE confidence derived from measurement precision, with its error range exposed
- Muscle tracking split into anatomical groups, with a front/back body map and a
  sortable, searchable weekly volume table
- Weekly volume rebuilt around muscle size classes and saturating assistance, with
  the week summarised as one overall band
- Secondary set counts for muscles worked but never targeted
- Supabase accounts and cloud backup
- Shared number entry panel, used for weigh-ins, workout weight and reps, and custom foods
- Saved workouts, repeatable and manageable
- Hybrid workout strain tracking, overall sleep quality scoring, and stress,
  sleep-efficiency and energy gauges
- Lift progress tracking with training insights, and a muscle weight progress drill-down
- Hydration tracking with a goal chart and custom liquids
- Rotating daily fitness reminders, editable, and the app icon
- A logging streak flame in place of the trends button
- Expanded evidence-based exercise catalog
- Food search ranked by provenance rather than source, matching regardless of word order
- Home screen rebuilt to the Figma layout as a full scrolling page, every card opening its own page
- Adaptive light and dark themes, the home palette applied across all screens,
  category bars on non-home tabs, and finger-tracking tab navigation
- Settings redesigned and simplified

### Fixed

- Only the lowest weigh-in of each day counts, in every weight calculation
- Intake averaged over calendar days, so weigh-in frequency cannot move TDEE
- TDEE recalculated when weigh-ins change
- Lean mass carried forward, and supplements counted on the home screen
- Row swipes work app-wide, and weigh-in edits and deletions confirm before applying
- The number entry panel sits above the keyboard instead of jumping to the top of the screen
- Latent crashes and wrong defaults closed across the diagram, pattern and account layers
- New profiles default to a 2000 birthdate rather than the epoch
- Right forearm labels corrected on the male front diagram
- High-severity HealthKit and duplicate-data errors resolved, and sync hardened
- Supabase session handling updated
- All build warnings cleared in the app and test targets
- Bottom tab bar stays anchored, category headings survive the header handoff,
  and cancelled tab highlights reset

### Performance

- Weekly volume computed once per redraw instead of once per muscle-diagram region
- Day membership compared against precomputed bounds rather than asking the calendar per row
- Data queries, history calculations, workout sync and backups optimised

### Docs

- Exercise count corrected and the current volume model described
- Archive coverage documented, including what a replace restore discards
- Muscle group and volume scale comments corrected, and the comparison model moved to tests

### Build

- Xcode recommended settings persisted
