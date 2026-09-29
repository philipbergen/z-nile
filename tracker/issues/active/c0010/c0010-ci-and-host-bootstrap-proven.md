---
id: c0010
type: chore
title: CI and host bootstrap proven
raft: R0010
depends_on: []
emergent: false
design: ready
created: 2026-09-28
---

# c0010: CI and host bootstrap proven

## Problem
Every guarantee in this repo rests on the gate (`scripts/check.sh`) and on the tracker CLI, but both have only ever run on the author's Mac:
- **CI**: `.github/workflows/check.yml` has never run, so a PR could go green locally and red on GitHub, or never be checked at all.
- **New hosts**: `scripts/setup.sh` hasn't been run on a clean machine.
- **Tracker**: the lifecycle (`new`, `raft`, `renumber`, `start`, `commit` + spend, review gate, `done`) was checked by hand once, but has no regression spec. A future tooling change could silently break attribution or the review gate.

Until this is fixed, "check.sh passes" doesn't mean "works on another machine".

## Non-goals
- Running Roblox itself in CI. That's c0020 (headless place tests) and a later Open Cloud issue.
- Windows hosts.
- Caching or speeding up CI beyond what the design needs.
- Testing the `gh` paths of `tracker start` and `done` (draft PR creation, `gh pr ready`) automatically. Executing this raft exercises them for real, and AC5 checks the result.

## Solution
- **One bootstrap path**: CI installs everything by running `scripts/setup.sh`, the same script a new host uses. Every CI run therefore proves SETUP.md on a clean Linux machine.
- **Manual trigger**: the workflow gains `workflow_dispatch`. `scripts/ci-verify.sh` dispatches CI for the current branch and waits for the result, so an agent can prove its branch is green without taking the PR out of draft.
- **Regression spec**: the tracker lifecycle gets a spec that drives the real CLI in a throwaway clone.

## Design

**`.github/workflows/check.yml`**:
- **Already on main**, landed in prep (design-review-001 F6):
  - the triggers `push` to `main`, `pull_request` (`opened, synchronize, reopened, ready_for_review`) and `workflow_dispatch: {}`. Keep the explicit `{}` form, because a bare `workflow_dispatch:` decodes to nil;
  - the job condition `if: github.event_name != 'pull_request' || github.event.pull_request.draft == false`. Drafts cost no CI; pushes and dispatches always run.
- **Still to do**: the steps below, plus an acceptance step.
- **Steps**:
  1. `actions/checkout@v4` with `fetch-depth: 0`. The tracker spec clones the repo and needs full history.
  2. `scripts/setup.sh`, with `env: GH_TOKEN: ${{ github.token }}`.
  3. **Active acceptance specs** (design-review-001 F8), so that sequestered specs are proven on Linux before `done`:
     ```yaml
     - if: github.event_name == 'workflow_dispatch'
       run: |
         files=$(find tracker -path '*/active/*/acceptance/*.spec.luau' | sort)
         if [ -n "$files" ]; then lune run tests/run -- $files; fi
     ```
     The run command must contain the literal `*/active/*/acceptance/*.spec.luau`, because the AC2 spec checks for it.
  The `CompeyDev/setup-rokit` action and the separate `lune setup` step are **removed**, because setup.sh does both.
  - setup.sh already runs `scripts/check.sh --full` as its last stage, so there's no separate gate step. The job fails if the gate fails.

**`scripts/setup.sh` changes (Linux/CI)**:
- **Auth** (design-review-001 F9): when `CI` is set, check auth with `gh api rate_limit >/dev/null` instead of `gh auth status`. The Actions installation token may be rejected by `auth status`, which calls `/user`. Keep `gh auth status` for humans.
- **Rokit rate limits**: when `CI` is set and `GH_TOKEN` is present, run `rokit authenticate github --token "$GH_TOKEN" --skip-parse --skip-verify` before `rokit install`. Without it, anonymous GitHub API calls can hit rate limits.
  - Both skip flags are required, because Actions tokens start with `ghs_`, which rokit 1.2.0's parser rejects (design-review-002 F3). Both flags are confirmed present in `rokit authenticate --help`.
  - Fallback if install still fails with the token: drop the step. Five tool downloads fit within anonymous limits; record which one was used.
- **CI PATH** (design-review-002 F2): when `GITHUB_PATH` is set, setup.sh runs `echo "$HOME/.rokit/bin" >> "$GITHUB_PATH"`. Later steps, including the acceptance step's `lune` and `place.load()`'s `rojo`, then find the tools.
- **PATH**: after `rokit self-install`, keep `export PATH="$HOME/.rokit/bin:$PATH"`. This is already there. Self-install edits shell profiles that CI doesn't source.
- **Git identity**: not needed by setup.sh. The tracker spec sets a local identity in its own clone.
- **`.luaurc` on Linux**: nothing to do. CI run 36511363843 (main, Linux) passed the Lune-types stage with the committed `~/.lune/.typedefs/<ver>/` alias. That was E2, resolved in prep; see F13.

**`scripts/ci-verify.sh`** (new, bash):
1. `branch=$(git branch --show-current)`. Fail if it's `main` or empty.
2. Fail with a clear message if `git rev-parse HEAD` ≠ `git rev-parse origin/$branch` after `git fetch origin "$branch"`. CI must test exactly the local HEAD.
3. Record `before` = the highest `databaseId` in `gh run list --workflow check.yml --limit 20 --json databaseId`, or 0 if there are none. Then run `gh workflow run check.yml --ref "$branch"`.
4. Poll `gh run list --workflow check.yml --branch "$branch" --event workflow_dispatch --json databaseId,headSha` until a run appears with `databaseId > before` **and** `headSha == HEAD`. Timeout 120 s, polling every 5 s. This avoids picking up a stale run for the same sha (design-review-001 F7).
5. `gh run watch <id> --exit-status --interval 10`. Exit with its status and print the run URL.

**Tracker lifecycle spec**:
- **File**: the acceptance spec `acceptance/tracker-lifecycle.spec.luau`, which `done` promotes to `tests/acceptance/c0010/`.
- **Setup**: it clones the repo's committed `HEAD` into `.cache/tracker-e2e` with `git clone -q <root> <dir>`, after deleting any previous copy. It removes `origin` and sets a local `user.name`/`user.email`.
- **Driving the CLI**: it runs `bash scripts/tracker.sh …` with `cwd` set to the clone. Because there's no remote, `start` and `done` skip push and `gh`.
- **No recursion**: its fixture raft's `check.sh` is a trivial `check "RC1: fixture" true`, so the spec never runs the gate inside itself.

### Scalability
- **CI time**: the full gate is about 20 s locally. setup.sh on a cold runner adds tool downloads, roughly 30–60 s. No cache yet; add `actions/cache` for `~/.rokit` only if CI goes over 3 minutes (a follow-up, not now).
- **Spec time**: the lifecycle spec runs about 15 CLI invocations, each a Lune start-up of roughly 0.1–0.3 s, so it stays well under 10 s.

### Maintainability
- One bootstrap script serves both humans and CI. If SETUP.md drifts, CI goes red.
- Tracker regressions show up as spec failures with named cases.

### Usability
- **Agents**: one command, `scripts/ci-verify.sh`, answers "is my branch green on CI?"
- **Humans**: they see a real check on every non-draft PR.

### Touched modules
- `.github/workflows/check.yml`
- `scripts/setup.sh`
- `scripts/ci-verify.sh`
- `SETUP.md`
- `scripts/tracker` (prep only: the post-promotion check in `done`, already landed)

### Affected specs
Changes under `scripts/` force a full run (`lune run scripts/affected` prints `ALL`). New: `acceptance/tracker-lifecycle.spec.luau` and `acceptance/ci-workflow.spec.luau`.

## Unknowns & experiments
- **E0 (run in prep: PASS)**: can a feature branch be dispatched with `gh workflow run check.yml --ref <branch>`?
  - Result on 2026-09-29: yes, once main's `check.yml` has `workflow_dispatch`. The probe branch `probe-dispatch` ran to success (run 36511379058) and was then deleted.
- **E1: Does `scripts/setup.sh` run clean on `ubuntu-latest` with only `GH_TOKEN`?** This includes the auth check from F9.
  - Method: the first CI dispatch.
  - **Result on 2026-09-28: PASS**, no fallback used. Run 36516452734 (dispatch, ubuntu-latest): `gh api rate_limit` auth, `rokit authenticate … --skip-parse --skip-verify`, self-install and `rokit install` all succeeded; the gate passed 27/27 and the dispatch-only acceptance step passed 31/31 across all 5 active acceptance specs. The job took 12 s, so no cache is needed.
  - Fallbacks:
    - `rokit self-install` fails non-interactively: extract the release zip and put `rokit` on PATH directly. Rokit also works without self-install when `~/.rokit/bin` is created by `rokit install`.
    - Rate-limited: the `rokit authenticate` step above.
- **E2 (run in prep: PASS)**: does the `.luaurc` `lune` alias resolve on Linux?
  - Result: yes. The main CI run using the old setup-rokit steps passed the full gate (20 specs).
  - If it ever regresses: only when `CI` is set, rewrite the alias to `$HOME/.lune/.typedefs/<ver>/` right after `lune setup`, and restore `.luaurc` in an `EXIT` trap.
- **E3: Does a dispatched run appear in `gh run list` within 120 s?**
  - Partially answered in prep: the probe's run was listed about 8 s after dispatch.
  - **Result on 2026-09-28: PASS.** `scripts/ci-verify.sh` found the run on its first polls; dispatch to result took 24 s. Timeout stays 120 s.
  - Fallback: raise the timeout to 300 s.
- **E4 (run in prep: PASS)**: the lifecycle spec passes 9/9 against the working tree, including the clean-tree, review, rollback and promotion paths.

## Regression guard
- **Existing specs stay green**: `tests/meta/architecture.spec.luau`, `tests/tooling/affected.spec.luau`, `tests/tooling/spend.spec.luau` and `tests/unit/smoke.spec.luau`.
- **New regression guard**: the lifecycle spec pins
  - ID stepping,
  - rejection of mixed-type rafts,
  - `renumber`,
  - `start` refusing designs that aren't ready,
  - spend lines equal to the diff,
  - the review gate,
  - acceptance promotion.

## Test plan
- **`acceptance/tracker-lifecycle.spec.luau`**: `allocates ids` → AC1; `rejects mixed-type raft` → AC1; `renumber rewrites references` → AC1; `start refuses undesigned` → AC1; `start branches and commits once` → AC1; `commit spend equals diff` → AC1; `done requires resolved review and promotes acceptance` → AC1.
- **`acceptance/ci-workflow.spec.luau`** (parses the workflow YAML with `@lune/serde`): `bootstraps via setup.sh` → AC2; `dispatchable` → AC2 (already passes); `runs active acceptance specs on dispatch` → AC2; `skips drafts only for pull_request` → AC2 (already passes); `no setup-rokit action` → AC2.
- **Lifecycle spec cases added in prep**: `done requires a clean tree and a resolved review`, and `done rolls back when a promoted acceptance spec fails`. `done` now type-checks the promoted specs, runs the meta spec and the specs themselves, and rolls back on failure (F3).

## Acceptance criteria

### Checked
- **AC1**: The tracker lifecycle spec passes.
- **AC2**: The CI workflow bootstraps with exactly `run: scripts/setup.sh`, which runs the full gate, with `GH_TOKEN`. It is dispatchable, runs the active acceptance specs on dispatch, and skips only draft `pull_request` events.
- **AC3**: CI is green for this branch's exact HEAD. Two things must both be true: `scripts/ci-verify.sh` succeeds, **and** check.sh independently finds a successful `workflow_dispatch` run of `check.yml` for `git rev-parse HEAD` (F5).
- **AC4**: `scripts/setup.sh` succeeds on an already set-up host, which shows it's idempotent.
- **AC5**: This branch has an open PR. That shows `tracker start`'s `gh` path works.

### Judged
None.

### Observed
None.

## Implementation steps
1. Edit `check.yml` as designed: the setup step is exactly `run: scripts/setup.sh`, plus the dispatch-only acceptance step. Commit.
2. `setup.sh` gets three changes: CI-only auth via `gh api rate_limit`, `rokit authenticate … --skip-parse --skip-verify`, and `GITHUB_PATH` export (design-review-002 F7). Commit.
3. Write `scripts/ci-verify.sh` and make it executable. Commit and push.
4. Run `scripts/ci-verify.sh`. Resolve E1–E3 using the fallbacks, and record the results in this document.
5. Update SETUP.md's CI section: it now uses setup.sh, and `ci-verify.sh` exists.
6. Run `scripts/tracker.sh check c0010`.

## Verification log
- 2026-09-28: `ci-workflow.spec` failed 3/6 before the change (setup-rokit present, no setup.sh step, no acceptance step). The lifecycle spec already passed 9/9 (E4). After the change, the first `scripts/ci-verify.sh` run (36516452734) succeeded; see E1 and E3. `scripts/tracker.sh check c0010` gave 5/5 PASS. The `rokit authenticate` path worked, so no fallback was recorded.
- 2026-09-28, final: review-001 F5 added `permissions: contents: read` to check.yml. The dispatch run from R0010 check.sh was green with it, and R0010 check.sh passed 6/6 from ~/code/pickman.
