---
id: c0010
type: chore
title: CI and host bootstrap proven
raft: R0010
depends_on: []
emergent: false
design: reviewed
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
- **Triggers**: `push` to `main`, `pull_request` (`opened, synchronize, reopened, ready_for_review`), and `workflow_dispatch`.
- **Job condition**: `if: github.event_name != 'pull_request' || github.event.pull_request.draft == false`. Drafts cost no CI; pushes and dispatches always run.
- **Steps**:
  1. `actions/checkout@v4` with `fetch-depth: 0`. The tracker spec clones the repo and needs full history.
  2. `scripts/setup.sh`, with `env: GH_TOKEN: ${{ github.token }}`.
  The `CompeyDev/setup-rokit` action and the separate `lune setup` step are **removed**, because setup.sh does both.
  - setup.sh already runs `scripts/check.sh --full` as its last stage, so there's no separate gate step. The job fails if the gate fails.

**`scripts/setup.sh` changes (Linux/CI)**:
- **Auth**: `gh auth status` must pass when `GH_TOKEN` is set (true for `gh` ≥ 2.x).
- **Rokit rate limits**: when `CI` is set and `GH_TOKEN` is present, run `rokit authenticate github --token "$GH_TOKEN"` before `rokit install`. Without it, anonymous GitHub API calls can hit rate limits.
- **PATH**: after `rokit self-install`, keep `export PATH="$HOME/.rokit/bin:$PATH"`. This is already there. Self-install edits shell profiles that CI doesn't source.
- **Git identity**: not needed by setup.sh. The tracker spec sets a local identity in its own clone.

**`scripts/ci-verify.sh`** (new, bash):
1. `branch=$(git branch --show-current)`. Fail if it's `main` or empty.
2. Fail with a clear message if `git rev-parse HEAD` ≠ `git rev-parse origin/$branch` after `git fetch origin "$branch"`. CI must test exactly the local HEAD.
3. `gh workflow run check.yml --ref "$branch"`.
4. Poll `gh run list --workflow check.yml --branch "$branch" --event workflow_dispatch --json databaseId,headSha,createdAt` until a run with `headSha == HEAD` appears. Timeout 120 s, polling every 5 s.
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

### Affected specs
Changes under `scripts/` force a full run (`lune run scripts/affected` prints `ALL`). New: `acceptance/tracker-lifecycle.spec.luau` and `acceptance/ci-workflow.spec.luau`.

## Unknowns & experiments
- **E1: Does `scripts/setup.sh` run clean on `ubuntu-latest` with only `GH_TOKEN`?**
  - Method: the first CI dispatch.
  - Fallbacks:
    - `rokit self-install` fails non-interactively: extract the release zip and put `rokit` on PATH directly. Rokit also works without self-install when `~/.rokit/bin` is created by `rokit install`.
    - Rate-limited: the `rokit authenticate` step above.
- **E2: Does the `.luaurc` `lune` alias (`~/.lune/.typedefs/<ver>/`) resolve on Linux after `lune setup`?**
  - Method: the CI gate's Lune type stage.
  - Fallback: in CI only, generate an absolute-path alias after `lune setup`, then `git checkout -- .luaurc` at the end. Record which one was used.
- **E3: Does `gh run list` show a `workflow_dispatch` run's `headSha` within 120 s?**
  - Method: the first `ci-verify.sh` run.
  - Fallback: match on `createdAt` being after the dispatch time, with the newest first.
- **E4 (already run in prep, PASS)**: the tracker lifecycle works in a remote-less clone: `start` skips push and PR, and `done` promotes `acceptance/`. The same sequence was run by hand during bootstrap.

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
- **`acceptance/ci-workflow.spec.luau`** (parses the workflow YAML with `@lune/serde`): `bootstraps via setup.sh` → AC2; `dispatchable` → AC2; `skips drafts only for pull_request` → AC2; `no setup-rokit action` → AC2.

## Acceptance criteria

### Checked
- **AC1**: The tracker lifecycle spec passes.
- **AC2**: The CI workflow bootstraps via `scripts/setup.sh` with `GH_TOKEN`, is dispatchable, and skips only draft `pull_request` events.
- **AC3**: CI is green for this branch's exact HEAD (`scripts/ci-verify.sh`).
- **AC4**: `scripts/setup.sh` succeeds on an already set-up host, which shows it's idempotent.
- **AC5**: This branch has an open PR. That shows `tracker start`'s `gh` path works.

### Judged
None.

### Observed
None.

## Implementation steps
1. Edit `check.yml` as designed. Commit.
2. Add the `rokit authenticate` step to `setup.sh` (CI only). Commit.
3. Write `scripts/ci-verify.sh` and make it executable. Commit and push.
4. Run `scripts/ci-verify.sh`. Resolve E1–E3 using the fallbacks, and record the results in this document.
5. Update SETUP.md's CI section: it now uses setup.sh, and `ci-verify.sh` exists.
6. Run `scripts/tracker.sh check c0010`.

## Verification log
