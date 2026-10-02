# Refute 007: R0210

All fixes were proven on a new combined prototype, `proto3-r0210` (local branch). It is `main` `5f7868f`, plus R0200's re-prepped prototype with c0510's specs promoted as if R0200 were done, plus `proto2-c0640`, with c0650 implemented. Its full gate passes: 801 cases, 122 files.

- F1: fixed.
  - **R0200's AC9:** the grep is written `"GIT_INDEX_""FILE"`, so `check.sh` doesn't name the variable (R0200 re-prep, refute 007 there).
  - **This raft's own specs:** they get allowlist entries in their promoted locations.
    - `tests/acceptance/c0650/adapt.spec.luau`: `GIT_CEILING_DIRECTORIES`, `GIT_CONFIG_`, `PICKMAN_TEST_FENCE`. c0650 adds it.
    - `tests/acceptance/c0660/fixture.spec.luau`: `GIT_DIR`, `GIT_WORK_TREE`. c0660 adds it.
    - Each entry has its reason, and the names were checked against the scan list.
    - The combined gate passes with these specs promoted.
  - **Scanning prepared specs where they sit:** not adopted. That would flag other rafts' sequestered specs before they run, which round 2 narrowed away. The real need, that the gate isn't broken by promotion, is met by the entries above, and `done`'s promote-check would catch any miss.
  - **Consequences:** none beyond the entries.
- F2: fixed, and run.
  - **Spec:** c0650's spec now runs `tracker.sh new` in a linked worktree of a fixture clone, which R0200 requires. The slugs are valid (`probe-one`, `probe-two`) and the fixture identity is `e2e@example.invalid`.
  - **Guarded case:** it asserts that the command succeeds, prints `not publishing`, leaves its stub as local changes, and moves neither HEAD nor `origin/main`.
  - **Unguarded case:** it asserts that the command publishes and doesn't say `not publishing`.
  - **Results:** run on `proto3-r0210`, 6 of 6 pass, and the scan cases fail before c0650's spec edits, as they should.
- F3: fixed.
  - **Where:** the decision moved into `publishing()` in `main.luau`, which already handles `PICKMAN_PUBLISH=0`, so a guarded command works locally.
  - **How it decides:** `main.luau` asks the guard's own script, through `pickman_guarded <dir>`, a new function in `scripts/lib/fence.sh`. It is memoised and prints once.
  - **Scan:** the function's name avoids the scanned `pickman_fence_` prefix; the first attempt, `pickman_fence_protects`, was flagged by the scan and renamed.
  - **Mutants:** P1 (no refusal), P3 (only the first protected repository) and P4 (refuse whenever the guards are on) are each killed. P2 (refusal after the fetch) no longer applies.
- F4: fixed by F3. The publisher names no guard variable, so it has no allowlist entry. The gate scans `main.luau` like any other script.
  - A1, A2 and A3 (the ceiling kept, the ceiling entry kept, a whole-file exemption) are each killed by c0650's two scan cases.
- F5: fixed.
  - R0210's Experiments section lists the Phase 1 work: E30 re-run on the real c0510 code, then RC1. It names `proto3-r0210` as the starting point.
  - The Rollout line says "as soon as R0200 is done".
  - c0660's testing-skill rule names the specs not yet converted (c0510's, c0640's, c0650's), to be converted when next edited. AC5 checks for that.
  - c0650's Problem says it means a check's own commands; specs started by a check have no network transport at all.

c0640 E30 has also been run, rather than left to Phase 1. c0510's 50 cases pass jailed, and again inside an outer sandbox that protects the repository, where the guard hooks are injected as on Linux.
