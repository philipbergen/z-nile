# Review 003: c0132 (design mode)
Inputs: prep head 391d8407 (`c0132.md`, `check.sh`, `acceptance/killed-report.spec.luau`, `design-review-002.md`, `design-refute-002.md`, `harvest.md`); prototype `proto-sweeper-report` at 74005845 (its `check.sh` and both copies of the spec are byte-identical to the prep's), merged onto today's origin/main 6427e53d in a scratch clone (main changed `tests/run.luau` and added `tests/lib/schedule.luau` since the prototype's base c809181f); CI run 40450384593; zz-review, z-design, zz-test, zz-arch skills and lessons, zz-test/jail-reach-proved-by-a-real-run, z-design/prototype-ci-green-before-the-round.
Dropped from review-002: F1, F3, F4 (fixed, verified below). F2's spec cases are right, but check.sh doesn't run them as criteria (F1 here).

Verified by running (macOS, Lune 0.10.5, load 18 to 40):
- `gh run view 40450384593`: `success`, head 74005845, gate (pickman) and gate (z-nile) both `success`.
- In the clone (prototype merged onto origin/main): `./zn check c0132` 7/7. `lune run tests/run --` over repo-fence, c0120 check-paths, c0076 sweeper, c0077 replace-file, c0078 jail-signals, c0079 watchdog, fence-inherited-env, sweeper-interlock and the promoted c0132 spec: `83 passed, 0 failed, 9 spec files`. Main's runner changes don't disturb AC7 (it copies `tests/lib` whole, `schedule.luau` included).
- Allow-list entry (Design, repo-fence): the same two keys, `PICKMAN_TEST_FENCE` and `sandbox-exec`, with c0078's reasons word for word, keyed to the one promoted file. The spec names them only as reads (`grep -n`: line 20 `process.env.PICKMAN_TEST_JAIL == "sandbox-exec"`, line 62 `process.env.PICKMAN_TEST_FENCE or ""`). That is as narrow as c0078's. `check.sh` names no guard (`grep -n "env -i\|sandbox-exec\|PICKMAN_TEST\|PICKMAN_FENCE\|GIT_DIR\|core.hooksPath"`: no hits).
- AC7 touches only `.cache`: ac.sh cds to `z-nile/`, so `$fx` is `z-nile/.cache/c0132-real`. Every `cp`, `git init/add/commit` (after the toplevel check, as `@example.invalid`) and run writes under `$fx`, the fixture is removed on a pass, and `rm -f .cache/c0132-jailed-ran` is relative to `z-nile/`.
- Kill guard: the fixture run is always a top-level run of a different checkout, and `enter()` always launches through `REAPER`, whose child calls `setpgrp(0, 0)` (jailed or not, `fence.luau` 738 and 905). So the group the probe writes is a fresh group that is never check.sh's own. The guard also requires `g > 1` and a member whose command line names `$fx/…/probe/outside`. I found no input that reaches another group.
- F3 is fixed: check.sh line 12 removes the marker before the spec runs.

### F1 [high] M17 and M18 pass `./zn check c0132` 7/7: AC2 doesn't name the two new cases, and `report()` ignores a failing case no criterion names
Where: `check.sh` lines 18 and 37–42 (AC2's case list); c0132.md Test plan (both cases mapped to AC2), Rules and mutants rows M17 and M18 ("run"), E9.
Evidence: in the clone, with M17 (` || ($x != 0 && $x != 1)` deleted from `fence.luau` 764), `./zn check c0132` printed `---- 7/7 criteria passed`. The spec run alone printed `FAIL … :: a specs group pgrep fails to read is unread, even when the launcher's own line reads` and `17 passed, 1 failed, 1 spec files`. With M18 (`!defined $me || ` deleted), `./zn check c0132` again printed `---- 7/7 criteria passed`. The spec has 18 cases. Every one is named in check.sh except these (search: each `it("…` in the spec looked up with `grep -qF` in check.sh):
```
UNLISTED: sets up
UNLISTED: a specs group pgrep fails to read is unread, even when the launcher's own line reads
UNLISTED: the launcher's own line not found is unread, even when the specs group reads
UNLISTED: cleans up
```
`report()` accepts `^[0-9]+ passed, [0-9]+ failed, 1 spec files$` with any failed count, and fails only on a FAIL line for a case it was asked about.
Critique: the refute says the two cases "kill M17 and M18". The spec does, but the item's acceptance contract doesn't: an executor can drop either half of the unread condition and get a green `./zn check`. That is exactly the review 002 F2 hole, now one level up. The author will be tempted to add the two names to AC2's list and stop there. But the mechanism is still open: the next case anyone adds to the spec fails silently the same way, and a failing `sets up` only counts because other cases fail with it.
Consequences: adding the names fixes today's two. Requiring `0 failed` for the whole run would make every criterion fail when any one does, so the per-criterion PASS/FAIL report would stop showing which outcome broke.
Recommendation:
- Add both case names to AC2's list in check.sh.
- In `report()`, once (or as its own first step), fail when a FAIL line names a case that no `check` line lists. Keep `sets up` and `cleans up` as named exceptions, since their failures show up through the cases that depend on them. Or list the spec's `it("` names and require each to be named by some criterion or exempted. Either way, an unnamed failing case turns the check red.
- Run M17 and M18 through `./zn check c0132`, not only the spec, and record that in E5 and the Rules and mutants rows. Rerun the other "run" rows the same way: E5 says the others were run "through the spec", which is the same blind spot.
Lesson: z-design/spec-design-correspondence

Candidate lesson (for the lead): zz-test: a check.sh that runs a spec once and judges named cases must also fail on a failing case no criterion names, because c0132 round 3 added two cases to the spec, mapped them to AC2 in the Test plan, and never listed them in check.sh, so both of their mutants passed `./zn check` 7/7. Check: run each mutant through `./zn check <id>`, not the spec alone. Does it go red?

Verdict: changes
