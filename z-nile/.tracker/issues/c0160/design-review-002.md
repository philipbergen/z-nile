# Review 002: c0160 (design mode)
Inputs: prep-check-paths-third 506854c0 (c0160.md, check.sh, acceptance/third-project.spec.luau, experiments/c0160-on-c0141.patch, design-review-001.md, design-refute-001.md). Reproduced on a scratch clone of today's origin/main b53c95bb (which holds R0062's rafting commit 2bd65f50 with c0141's E4 fix). On it I applied c0141's prototype (`git diff d24aabc8 origin/proto-check-paths-home -- z-nile/tests/acceptance/c0120`) and then c0160's patch, promoted c0141's two specs from main, and put c0160's spec in `tests/acceptance/c0160/` and its issue folder from 506854c0. Every run used rokit Lune 0.10.5 under tests/run on macOS.
Dropped from review-001: none. F1, F2 and F3 are fixed, as verified below.

Round-1 answers re-run:
- F1:
  - c0160's spec passed `6 passed, 0 failed` three times.
  - With c0120's check-paths and finished specs, c0141's two specs (by glob) and `tests/meta/architecture.spec.luau`, it gave `23 passed, 0 failed, 6 spec files`. So E4 no longer reddens the architecture spec on today's main.
  - M8 (checkpaths' `checkoutHomes` returns `{ "pickman", "z-nile" }`) gave `5 passed, 1 failed`. M9 (the same in rewrites) gave `5 passed, 1 failed`. The failing case in both was "the default homes are the registry's…".
  - Three mutants that are not in the table:
    - Both defaults read `projects.load(".")` with no `rev-parse`: `4 passed, 2 failed`. The in-process cases kill it, because `.` from z-nile/ has no registry.
    - rewrites' default is the registry plus `pickman`: `5 passed, 1 failed`.
    - `rewrites.rewrite` calls `literals(text, {})` instead of the default: finished.spec gave `5 passed, 1 failed` ("rewrites a finished check.sh's moved paths from its home"). The call site is pinned.
  - `./zn check c0160` on the clone: `4/4 criteria passed`.
  - Linux CI 40447016242: `success`, gate (z-nile) success, gate (pickman) success, head e743fc1f on `ci-c0160-proto`. Its `z-nile/tests/acceptance/c0160/third-project.spec.luau` (through `gh api …/contents?ref=e743fc1f`) is byte-identical to the prep's spec.
- F2:
  - AC4 is `"$PWD"/tests/acceptance/c0141/*.spec.luau`, and it passed above.
  - E4's record is real: 2bd65f50 ("tracker: raft R0062 Check guards (c0139, c0141) (#164)") on origin/main builds uses-module.spec's needle from parts and logs it in c0141's Verification log. See F1 below for its wording.
- F3: the own-work case asserts that `../tern/src/new/init.luau` is among the words read. The fix is sound.

Repository safety: the new case writes only `.cache/c0160-default/`. It runs `git init -q` there, with no commit, and runs a child `lune` whose cwd is that fixture. The child reads (`git rev-parse --show-toplevel`, the fixture's registry) and writes nothing. It removes the fixture at the end. Nothing reaches the real repository.

Scope (`./zn capture c0160`): every outcome of the captured Problem has a Design and AC1–AC3: a third root's items, its home's paths, the `(from <home>)` line, the Touched exemption, `byHome`, and `<home>/` read from the registry. G1 and G2 are recorded as "Decided with the user (2026-10-26)".

### F1 [low] E4 and the prep base still describe c0141's fix as future, and the prep is 52 commits behind origin/main
Where: c0160.md Unknowns E4 ("stream D fixes it in c0141's rafting branch before c0141 is grouped"); Design "(2026-10-26, main at 1eadf5a5 …)"; Verification log ("main 5a5c05dc").
Evidence: `git merge-base --is-ancestor 2bd65f50 506854c0` reports that the prep lacks R0062. `git log --oneline 506854c0..origin/main | wc -l` gives 52. The fix has landed in 2bd65f50, the rafting PR #164.
Critique: an executor who reads E4 will look for a pending fix that has already landed. My runs on today's main pass, so nothing breaks.
Consequences: none.
Recommendation: when the prep merges origin/main, reword E4 to cite 2bd65f50 (R0062's rafting PR #164) as the landed fix. No spec or check change is needed.

### F2 [low] `rewrites.rewrite` reads the running checkout's homes even when its world is a fixture checkout, which the Solution's "the checkout being scanned" doesn't say
Where: c0160.md Solution ("the homes read from the registry of the checkout being scanned"); Design change 2 ("`rewrites.rewrite` keeps calling it with one argument").
Evidence: finished.spec.luau:134–182 calls `rewrites.rewrite(<fixture text>, home, rewrites.world(FX, …))`. `World` (rewrites.luau:260) carries no `top`, so the homes come from the real checkout's registry and not from FX's. Today both register pickman and z-nile (finished.spec.luau:123), so the result is the same.
Critique: the design states this exception in change 2, but the Solution's sentence covers both readers. A later fixture that registers a third project and calls `rewrite` would silently read the real checkout's homes.
Consequences: threading the homes through `World` would add an argument to `rewrites.world` and change finished.luau, which this chore keeps out of scope.
Recommendation: reword the Solution to say that the scan reads the scanned checkout's registry and that `rewrites.rewrite` reads the running checkout's. Add a one-line comment at `rewrites.rewrite`'s call to `literals` saying the same. No spec change is needed.

Verdict: approve
