---
id: R0010
type: chore
title: Foundation
single: false
issues: [c0010, c0020]
design: reviewed
created: 2026-09-28
---

# R0010: Foundation

## Theme
Both issues make "`check.sh` passes" a trustworthy statement before any gameplay exists.
- **c0010** proves the gate and the tracker run identically on any host, including CI.
- **c0020** extends the gate from pure Logic to what Rojo actually builds for Roblox.

They touch the same area (test infrastructure: `scripts/`, `tests/lib`, CI) and share one risk: an unverified assumption about the environment. Both are chores.

## Whole-raft design
```
scripts/setup.sh ──runs──▶ scripts/check.sh --full ──▶ lune run tests/run
      ▲                                                   ├─ tests/unit, tests/tooling, tests/meta
      │ (CI: .github/workflows/check.yml)                 ├─ tests/place/*        (c0020, via tests/lib/place.luau → rojo build → @lune/roblox)
      │                                                   └─ tests/acceptance/*   (promoted by tracker done)
scripts/ci-verify.sh (c0010) ── gh workflow run + watch ──▶ same workflow, exact HEAD
scripts/affected.luau ─▶ scripts/lib/graph.luau (c0020: PLACE_LIB implicit deps on src/**, default.project.json)
```
- **Interfaces between the issues**:
  - `graph.PLACE_LIB` and `graph.affectedSpecs(g, changed, isSpec)` keep their existing signature; only the behavior extends.
  - c0010's CI runs whatever c0020 adds, so c0020's specs must run on Linux. `rojo build` and `@lune/roblox` both run on Linux.
- **No changes to `tracker/architecture.md`**: neither issue adds game features.

## Order & dependencies
1. **c0020 first.** It's purely local and fully specified.
2. **c0010 second.** Its AC3 (CI green) then also proves on Linux both c0020's place tests and every active acceptance spec, through the dispatch-only acceptance step (F8).

## Experiments phase
Most of this raft's unknowns concern the CI environment and are resolved by c0010's first `scripts/ci-verify.sh` run.
- **c0010**: E1 (setup.sh on ubuntu, including auth) and E3 (the dispatch run appearing). E0 (dispatching a branch) and E2 (the `lune` alias on Linux) were run in prep and PASSED.
- **c0020**: E1 and E2 were run in prep and PASSED. E3 is an accepted risk, deferred to the first relative require, with OC1.
- **Order**: push c0020's work early, then dispatch CI once, to surface E1–E3 before finishing c0010.

## Exit criteria
Implemented by `check.sh`:
- **RC0**: the full repo gate passes, and c0010 and c0020's `check.sh` pass. That includes CI green on this branch's HEAD (c0010 AC3), and the draft PR existing (c0010 AC5).
- **RC1**: after this raft, the gate's place tier runs. `tests/place/` contains at least one spec file, and running them all (`lune run tests/run -- $(find tests/place -name '*.spec.luau')`) reports 0 failures. An empty or missing directory fails (F1).

## Risks & rollback
- **Risk**: CI on Linux behaves differently from macOS (paths, `~` expansion, `sed -i`). Mitigation: setup.sh and check.sh must stay POSIX-bash, with no `sed -i ''`. Rollback: revert the workflow file; local gates are unaffected.
- **Risk**: GitHub API rate limits in `rokit install`. Mitigation: `rokit authenticate` in CI.

## Addressed during execution

