# Review 001: c0062 (stream mode)
Inputs: `git diff R0025-ready-raft...ws-c0062` (10 files: the 5 parts, trackerfix.luau, repo-fence.spec, c0059 adapt.spec, c0062.md, deletion of commands.spec), c0062.md, its check.sh, `scripts/tracker.sh check c0062` (5/5 PASS, run in the stream worktree). Every case body compared by script against `git show R0025-ready-raft:tests/acceptance/c0053/commands.spec.luau`.

Checked and clean:
- Scope: only c0062's Touched modules and its document. No sequestered file touched.
- 23 original case names present exactly once; the only new cases are the four "sets up the <part> fixture" cases the Design calls for.
- Assertions: after normalising, the per-case diff shows no dropped, weakened or changed expect. Differences are plumbing only: R0010 renamed R0001 in the start part (a label; every use consistently renamed), `run(...)` replaced by `fixture.exec(...)` (the same `.ok` toBe(true)), the lost case's `tr(lost, ...)` replaced by `trLost(...)` (same asserts, `PICKMAN_PUBLISH=0` env kept), `fixture.physical(".")` for root. The stamp case is slightly stronger (each of the three results must be `.ok`, each line matched against the stamp pattern, and the distinctness assertions are unchanged).
- Seeds: claim seeds c0230, so `new issue` gives c0240/c0250 as asserted; start seeds R0001 and c0240 as `preparing-...` with design draft, plus `raft: R0001` on c0240 (recorded deviation, matches what the original capture worktree's local "members" commit held); new, prep and sync need none. Each part passes alone (E1) and together.
- Fixtures: `c0053-commands-{new,claim,prep,start,sync}` are distinct, and no `.cache/c0510-*` or other shared path remains. The tracker-claim files live inside each part's own worktrees.
- trackerfix.luau: has the Design's API (`new`, `tr`, `trOk`, `elsewhere`, `stub`, type `Fixture`); every git and tracker.sh call goes through `fixture.git`/`fixture.exec`; raw `process.exec("git")` only in `create` for init/clone to named paths; identity is `<name>@example.invalid`; no GIT_DIR/GIT_INDEX_FILE/GIT_WORK_TREE or other banned name (they stay only in commands-new's `setHook`, as before).
- Exceptions: the `lost` case uses raw `process.exec` with a comment giving the reason; its `outer` repos are inside the part's `.cache` directory. commands-sync repeats a local `create` (same init/clone-only use).
- repo-fence ALLOWED: one line changed, only the key (`commands.spec.luau` to `commands-new.spec.luau`); same three names, same reason "fixture hook"; publish.spec's entry untouched.
- adapt.spec: only the C0510 definition changed (readDir of `commands-*.spec.luau`, sorted, plus publish.spec); case names and assertions untouched.

### F1 [low] JC1 evidence holds only against the same-machine baseline, and the work done grew
Where: c0062.md, Verification log (JC1 baseline and "after")
Evidence: the baseline runs were 37.0, 46.1 and 56.6 s at load 4-5 (1 min), the after runs 14.2, 13.4 and 13.8 s at load 2.9-3.6, run afterwards, not interleaved. Against the prep baseline (27.8 s) the after mean (13.8 s) is 49.6% to 51% (the log says 50.8%). The parts' own times alone sum to 39.7 s (9.7 + 6.9 + 11.7 + 7.1 + 4.3), more than the single file's 27.8 s, because each part rebuilds a fixture and runs a setup case. In the full gate under load 17.8, commands-prep alone took 28.4 s.
Critique: the 30-38% ratio is real wall-clock evidence on this machine, but the load difference favours "after" and the gain relies on `--jobs 4` parallelism; on a saturated pool the extra ~10 s of total work costs, not saves. The rubric's wording (same machine and load) is only loosely met.
Consequences: none for the code. If the whole-raft reviewer wants firmer evidence, rerun baseline (git stash of the parts is not needed: use `git show` of the old file in a scratch copy) and after back to back, two alternations.
Recommendation: my view is that JC1 passes, narrowly and with a confounded measurement (the parts are about 30-38% of the same-machine baseline, about 50% of the prep baseline). The raft reviewer should rule, ideally after an interleaved rerun.

### F2 [low] Stamp case would hang if a spawned call errors
Where: tests/acceptance/c0053/commands-new.spec.luau, the "stamps from processes started together differ" case
Evidence: `pending -= 1` runs after `tr(...)`. If `tr` raised inside the `task.spawn`ed function, `pending` never reaches 0 and the `while pending > 0 do task.wait()` loop never ends (the runner's timeout is the only exit).
Critique: `fixture.exec` is documented not to raise for command failure, but it does raise on a fixture refusal.
Consequences: a hang instead of a failure message in a rare case; the fix (wrap in pcall and record the error in `outs`) is small and adds one assertion.
Recommendation: optional; `pcall` around `tr` and assert `outs[i] ~= nil` per slot.

### F3 [low] adapt.spec's C0510 list can silently shrink to just the publish spec
Where: tests/acceptance/c0059/adapt.spec.luau, `c0510Specs`
Evidence: if no file matches `^commands%-.+%.spec%.luau$` (a rename), the list holds only publish.spec.luau and the cases still pass.
Critique: the check.sh AC2 of c0062 requires four or more parts, which covers it today; the adapt spec itself has no floor.
Consequences: a one-line `error` when the match list is empty, which does not change any case name.
Recommendation: optional.

Verdict: approve
