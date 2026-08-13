---
name: pr
description: "Pre-merge orchestrator for SuperFit. Runs the branch through verify, review, docs-drift, changelog, version bump and knowledge-base refresh, then hands over a commit command. Use when a branch is ready to merge, when the user says /pr, ship it, prep this branch, or asks what is left before merging."
---

# /pr

The pre-merge pipeline for SuperFit. One command that takes the current branch from
"code is written" to "ready to merge", updating everything that surrounds the code
and would otherwise drift: the changelog, the build number, the docs, the knowledge
graph.

It is a **local** flow. There is no `gh` on this machine and pushing is forbidden,
so this never opens a GitHub PR, never commits, and never pushes. It ends by
printing a commit command for the repo owner to run.

## Usage

```
/pr                  # full pipeline on the current branch
/pr --minor          # also bump MARKETING_VERSION minor (1.0 -> 1.1)
/pr --major          # also bump MARKETING_VERSION major (1.0 -> 2.0)
/pr --skip-review    # skip the review step entirely
/pr --full           # review everything since main, not just what is new (expensive)
/pr --dry-run        # report every step, write nothing
/pr --since <ref>    # compare against <ref> instead of main
```

## Hard rules

These override anything inferred below.

1. **Never run `git commit`, `git merge` or `git push`.** Prepare the command in a
   fenced `bash` block and let the repo owner run it. Reading git state is fine.
2. **Never pipe `xcodebuild` through `grep | head`.** That makes `$?` the exit of
   `head` and reports success on a build that never ran. Redirect to a file, check
   `$?`, then grep.
3. **A failing build or test suite stops the pipeline.** Do not bump a version, do
   not write a changelog entry, and do not refresh the graph on a red branch.
   Report the failure with the actual output and stop.
4. **Docs drift is reported, never silently fixed.** Say what looks stale and offer
   to fix it. The user decides.
5. **Stop and report** rather than guessing if the branch is `main`, the working
   tree is empty, or there are no commits since the base.

## Step 0 — Preflight

```bash
cd /Users/stephenh/SuperFit
git branch --show-current
git status --short
git log --oneline main..HEAD
```

- If the current branch is `main`, stop: "Already on main — nothing to prepare."
- If `git log main..HEAD` is empty, stop: "No commits since main."
- Note uncommitted files. They are *not* automatically part of this — list them and
  ask whether they belong in the merge before touching anything.

Print a one-line plan (`N commits, M files changed`) and continue.

## Step 1 — Verify (hard gate)

Run xcodegen **only if** files were added, deleted or moved — check the diff for
added/deleted paths under `ios/`:

```bash
git diff --name-status main..HEAD -- ios/ | grep -E '^(A|D|R)' | head
```

If any, or if untracked source files are being included:

```bash
cd /Users/stephenh/SuperFit && xcodegen generate
```

Then build and test. Check the simulator name first — it changes with Xcode:

```bash
xcrun simctl list devices available | grep iPhone
```

```bash
cd /Users/stephenh/SuperFit && xcodebuild -project SuperFit.xcodeproj -scheme SuperFit \
  -destination 'platform=iOS Simulator,name=iPhone 17e' test > /tmp/pr-test.log 2>&1
echo "exit=$?"
grep -E "error:|✘|Test run with" /tmp/pr-test.log | tail -20
```

**Non-zero exit stops the pipeline.** Report the failing tests with their output.

## Step 2 — Review what is genuinely unreviewed

Skip entirely on `--skip-review`.

**Scope is the whole cost of this pipeline.** Every other step is flat — build
output is grepped down to one line, graphify costs no tokens at all, the changelog
reads commit subjects only. This step is the sole part that scales with the size of
the diff, so scoping it correctly is what keeps `/pr` cheap enough to run often.

The scope is **not** everything since `main`. On a long-lived branch that is
hundreds of files of already-merged, already-reviewed work — on `xcode-launch` it
was 193 files across 82 commits, which would have cost more than everything else
combined to re-review code from weeks ago.

Review instead:

1. **Uncommitted working-tree changes** — always unreviewed by definition.
2. **Commits since the last `/pr` run**, read from `.claude/pr-last-reviewed`.

```bash
cd /Users/stephenh/SuperFit
LAST=$(cat .claude/pr-last-reviewed 2>/dev/null)
if [ -n "$LAST" ] && git cat-file -e "$LAST" 2>/dev/null; then
    echo "reviewing commits since $LAST"
    git diff --stat "$LAST"..HEAD
else
    echo "no marker — reviewing uncommitted changes only"
fi
git diff --stat HEAD
```

If the marker is missing (first run, or a fresh clone — it is gitignored and
per-machine), review the uncommitted changes only and **say so**, offering `--full`
rather than silently reviewing less than the user expects.

`--full` overrides all of this and reviews everything since `main`. It is the
expensive path; only take it when asked.

Invoke the `code-review` skill on the resolved scope. Report findings ranked by
severity. Do **not** auto-apply fixes — the user asked for a review flow, and a
review that silently rewrites the code is not a review.

If findings are severe (correctness bugs, not style), say so plainly and ask
whether to continue the pipeline or stop and fix first.

## Step 3 — Docs drift check

Report only. Compare the diff against the documentation that describes it:

- `README.md` — user-facing feature descriptions and **any quoted count**
  (exercise catalog size, activity count, micronutrient count, test count). These
  drift constantly; verify numbers against the source rather than trusting them.
- `docs/ALGORITHMS.md` — if an engine's maths, constant or threshold changed, the
  reasoning belongs here, not in a comment.
- `docs/DATABASE.md` — if a `@Model` was added or a field changed.
- `docs/ARCHITECTURE.md` — if a layer boundary or provider moved.
- `/Users/stephenh/Downloads/CLAUDE.md` — the operational layer, **outside the
  repo**. Landmines, invariants, performance notes, conventions. A new trap that
  cost real time belongs here.

Checks worth running mechanically:

```bash
# quoted counts that go stale
grep -c '^\s*Entry("' ios/SuperFit/Core/Training/ExerciseLibrary.swift   # exercises
grep -rc "@Test" ios/SuperFitTests/*.swift | awk -F: '{s+=$2} END {print s}'  # tests
```

For each drift found, state the file, what is stale, and what it should say.

## Step 4 — CHANGELOG

Maintain `CHANGELOG.md` at the repo root, newest first, Keep a Changelog style.
Create it if absent.

Group commits since the base by their existing prefix. The full set in use, read
off the real history — not just the four in CLAUDE.md:

| commit prefix | section     |
|---------------|-------------|
| `Feat - `     | Added       |
| `Fix - `      | Fixed       |
| `Perf - `     | Performance |
| `Refactor - ` | Changed     |
| `Copy - `     | Changed     |
| `Docs - `     | Docs        |
| `Build - `    | Build       |
| `Merge`       | *dropped*   |

```bash
git log --format='%s' main..HEAD
```

Write entries in the repo's voice: sentence case, plain words, one line each, no
bullet-nesting. Strip the prefix — the section already says what kind of change it
is.

**Dedupe before writing.** Cherry-picks and merges duplicate subjects verbatim; the
seed history had four such pairs. Drop merge commits and `wip`. Where several
commits are obviously one piece of work (six separate fixes to the same header
handoff), collapse them into one line that says what changed, not how many attempts
it took.

An unrecognised prefix is not a reason to drop a commit — put it under **Changed**
and mention the unknown prefix in the summary so the table can be extended.

Entry heading is the resulting version from Step 5 and today's date:

```markdown
## 1.0 (build 4) — 2026-08-13

### Added
- Custom water and liquid hydration tracking

### Fixed
- Anchor the number entry panel above the keyboard and speed up the day filters
- Compute the weekly volume once per redraw instead of once per diagram region
```

## Step 5 — Version bump

`project.yml` holds both:

```yaml
MARKETING_VERSION: "1.0"
CURRENT_PROJECT_VERSION: "1"
```

- **`CURRENT_PROJECT_VERSION` bumps by 1 whenever Step 4 wrote a changelog entry**
  — not on every run. It is a build counter and means nothing to a user, so
  automating it is safe; bumping it for a run that changelogged nothing is not,
  because it produces a build number no entry describes. If there are no new
  commits since the newest changelog heading, say "already prepared" and leave both
  the changelog and the version alone.
- **`MARKETING_VERSION` only changes when asked** via `--minor` / `--major`. Never
  infer it from commit messages — a version number is a claim about the product,
  and guessing it wrong is visible to users and awkward to walk back.

Edit `project.yml` directly. It is committed; the generated `.xcodeproj` is not, so
regenerate afterwards:

```bash
cd /Users/stephenh/SuperFit && xcodegen generate
```

## Step 6 — Knowledge base

Refresh the graph so it matches what is about to merge:

```bash
cd /Users/stephenh/SuperFit && graphify update
```

**The working directory does not matter, and assuming it does was a real bug in an
earlier version of this skill.** `graphify update` resolves its output against the
scan root recorded in `graphify-out/.graphify_root`, so it always writes to
`SuperFit/graphify-out/` regardless of where it is invoked. That directory is
gitignored. Treat it as the canonical graph and query from inside the repo.

It also **re-clusters and re-derives community names** on every run, so any curated
labels are replaced by auto-generated ones (a community named after its largest
node — `TrainingView` rather than `Training View Rows`). Do not hand-label
communities expecting them to survive; if readable names matter, relabel after the
last update rather than before.

Free — code re-extraction is pure AST, no LLM tokens.

Two cases it does **not** cover, and which must be reported rather than assumed:

- **Docs changed** (`README.md`, `docs/*.md`): `graphify update` is code-only. Say
  that a full `/graphify --update` is needed and that it costs tokens. Do not run
  it automatically.
- **A new language grammar was installed**: an unchanged file is skipped no matter
  what the parser can now read. That needs a full rebuild, not an update.

## Step 7 — Record the review point

Only if Step 2 actually ran (not on `--skip-review`), and only after the verify
gate passed. Record the commit that was reviewed up to, so the next run reviews
forward from here instead of repeating this diff:

```bash
cd /Users/stephenh/SuperFit && git rev-parse HEAD > .claude/pr-last-reviewed
```

It is gitignored and therefore per-machine. That is deliberate: a tracked marker
would carry one machine's SHA into the other's auto-merge and conflict on a file
whose whole purpose is to be rewritten every run. The cost of it being local is
that the first run on the second machine reviews only uncommitted changes and says
so — which is the safe direction to fail.

**Caveat worth stating in the summary:** the marker records the last *commit*
reviewed, so uncommitted changes reviewed on this run are not covered by it. They
will be reviewed again next run if still uncommitted. That is correct — code that
has not been committed can still change.

## Step 8 — Hand over

Print a summary and the commit command. Never run it.

```
Branch xcode-launch — ready to merge

  verify      380 tests passed, build clean
  review      2 findings (1 correctness, 1 simplification)
  docs        README exercise count stale: says 224, source has 231
  changelog   3 entries added under 1.0 (build 4)
  version     CURRENT_PROJECT_VERSION 3 -> 4
  graph       updated (code only; docs/ changed, full re-extract needed)
```

Then the command, staging only what the pipeline touched:

```bash
git -C /Users/stephenh/SuperFit commit -m "Build - Bump build number and update the changelog" -- CHANGELOG.md project.yml
```

If docs drift was found, follow with the specific fixes offered as a separate
question — do not fold an unreviewed doc edit into the version commit.

## Conventions this skill inherits

- Commit titles: `Feat - `, `Fix - `, `Docs - `, `Build - ` plus one sentence-case
  line. Plain words, no bullet lists.
- Tests are Swift Testing (`@Test` / `#expect`), not XCTest.
- Reasoning goes in `docs/ALGORITHMS.md` or a test doc-comment with the measured
  number — not in a comment restating the code.
- When a request has a technical flaw, say so with the numbers and recommend the
  better option before building.
