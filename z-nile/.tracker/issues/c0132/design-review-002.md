# Review 002: c0132 (design mode)
Inputs: prep head 09e209d0 (`c0132.md`, `check.sh`, `acceptance/killed-report.spec.luau`, `design-refute-001.md`, `harvest.md`); prototype `proto-sweeper-report` at e66bd646 (its `check.sh` and spec are byte-identical to the prep's), applied to today's origin/main b53c95bb in a scratch clone; CI run 40448666640; zz-review, z-design, zz-test, zz-arch skills, `./zn lessons --when design`, zz-test/jail-reach-proved-by-a-real-run.
Dropped from review-001: none withdrawn; F1 to F6 are fixed as the refute says (verified below), apart from the gate breakage the F1 and F5 fixes brought in (F1 here).

Verified by running (macOS, Lune 0.10.5, loads 24 to 40):
- `./zn check c0132` on the prototype applied to origin/main (scratch clone): 7/7. In `.worktree/proto-sweeper-report`: 7/7, and the real repository's `.git/config`, `git config --list --show-origin`, the main checkout's status, the prototype branch's ref and HEAD, and `.git/worktrees` were the same before and after. AC7's fixture lives in `z-nile/.cache/c0132-real` and is removed when it passes; its git commands run only after the toplevel check, and its commit uses `@example.invalid`. I found no path from AC7 to the real repository.
- AC7's three readings, looped 8 times in the clone (each run's who line printed): inside `watchdog alive; 0 other … from inside the jail, or the sweeper alone after the specs ended` 8/8; alone `watchdog alive; 5 other … the sweeper's pid alone was signalled` 8/8; outside `watchdog gone; 0 other … from outside the jail` 8/8.
- Mutants on the prototype's `fence.luau`, through `./zn check c0132`: M13 fails AC2, M14 fails AC7, M15 fails AC1, M16 fails AC2. Two unlisted mutants survive (F2).
- A killed group member left unreaped is not listed by macOS `pgrep -g` (a zombie checked by hand), and 200 runs of a group killed from inside, with the parent's `pgrep` right after its `waitpid`, left nothing listed (`hits 0 of 200`). So I found no race that turns a group signal into a pid reading.
- c0167 and c0168 exist on origin/main; `check.sh` uses `grep -F -A1`.

### F1 [high] CI run 40448666640 failed: the revised check.sh and spec turn the z-nile and pickman gates red, from the moment the prep lands
Where: `check.sh` lines 65–66, 82 (AC7's copy list, the `tests/probe/` path and `PICKMAN_TEST_FENCE=`); `acceptance/killed-report.spec.luau` lines 20 and 62 (`"sandbox-exec"`, `PICKMAN_TEST_FENCE`), added by the F5 fix; c0132.md E5 ("its result not yet in"), Overrides, Touched modules.
Evidence: `gh run view 40448666640` (e66bd646): `completed failure`. gate (z-nile) `1236 passed, 2 failed`, gate (pickman) `1414 passed, 1 failed`:
- `tests/tooling/repo-fence.spec.luau :: no spec, check.sh or script switches a guard off or points git elsewhere` (pickman's `tests/meta/fence.spec.luau` runs the same scan): `z-nile/tests/acceptance/c0132/killed-report.spec.luau names PICKMAN_TEST_FENCE`, `… names sandbox-exec`, `z-nile/.tracker/issues/c0132/check.sh names PICKMAN_TEST_FENCE`.
- `tests/acceptance/c0120/check-paths.spec.luau :: every unfinished item's check.sh, in every project root, names only paths that exist from its home`: `c0132/check.sh: .gitignore`, `rokit.toml`, `tests/probe/`, `z-nile/.luaurc`, `z-nile/lib/ac.sh`, `z-nile/lib/fence.sh`, `z-nile/lib/git-hooks`, `z-nile/tests/lib`, `z-nile/tests/run.luau` (all `(from z-nile)`).
I reproduced both in the scratch clone: `lune run tests/run -- tests/tooling/repo-fence.spec.luau tests/acceptance/c0120/check-paths.spec.luau` gives `12 passed, 2 failed`, with the same lines. The sequestered spec isn't scanned, but `check.sh` is: the prep PR's own gate fails both scans, and after `done` the promoted spec fails repo-fence a second time. The prior CI runs passed because the round-1 `check.sh` had no AC7 and the spec didn't read the lock.
Critique: the gate the prep must pass is red, and the document records the run as pending. The fix the author will want is to add the check.sh to repo-fence's allow-list. But a prep lands only tracker files, so it can't edit `repo-fence.spec.luau`. And a check.sh that clears the runner's marker is exactly what the scan exists to refuse.
Consequences: the spec's two names are the same ones c0076's and c0078's specs have reviewed allowances for (`reads the run's lock to find the top process, outside the jail`, `tests whether it runs jailed`). The allow-list accepts a key for "an unfinished item's spec where done will promote it" (repo-fence line 585), so the execution can add it before `done`. That is a guard change, so the Design, the Touched modules and the review have to name it. The check.sh can't get an allowance in the prep, so it must stop naming the marker. A fixture run started under `env -i` (with `HOME`, `PATH` and `TMPDIR` passed on explicitly) is a top-level run without naming it. Then `PICKMAN_TEST_FENCE` from an enclosing run can't leak in either. The copy list has to name paths check-paths reads as existing from `z-nile/` (`tests/run.luau`, `tests/lib`, `lib/ac.sh`, … under `"$top/z-nile/"`, and the root files through `"$top/…"`), and the probe path has to be built from `$fx`.
Recommendation:
- Rewrite AC7's fixture set-up so `check.sh` names neither `PICKMAN_TEST_FENCE` nor a path missing from `z-nile/`, for example with `env -i` and `$top`/`$fx`-built paths.
- Add to the Design and the Touched modules the `repo-fence.spec.luau` allow-list entry for `z-nile/tests/acceptance/c0132/killed-report.spec.luau`, with c0078's two reasons, and add a Regression guard line for it.
- Push the prototype with both changes, record a green `z-nile/ci-verify.sh` run (both gates) in E5, and only then cite it. Run the full macOS gate on the prototype too, since these scans are what a `./zn check` alone never runs.
Lesson: z-design/prove-specs-pass-on-a-prototype, z-design/rerun-skipped-checks-after-edits

### F2 [medium] Each of the two "unread" triggers is unpinned: dropping either one keeps every check green
Where: Design `fence.REAPER` step 2 ("`pgrep` exits 0 (found) or 1 (none); any other status, or no `$me`, makes the group **unread**"); Rules and mutants row M13; spec "a group pgrep can't read is unread, never an empty group".
Evidence: on the prototype in the scratch clone, `./zn check c0132` stays `7/7` with each of these mutants:
- M17: ` || ($x != 0 && $x != 1)` deleted (a failed specs-group read is never unread);
- M18: `!defined $me || ` deleted (a failed own-group read is never unread).
The one case removes `pgrep` from PATH, so both triggers fire at once and either alone kills M13. A run where only one of the two reads fails is the load case review 001 F2 named (a fork that fails with `EAGAIN` for one backtick and not the other). Under M18 the watchdog is never matched, so it prints `watchdog gone` with the specs listed: the "watchdog and sweeper signalled" reading, from a read failure. Under M17 it prints `watchdog gone; 0 other …; the whole group was signalled from outside the jail`.
Critique: the guard this fix added is exactly what F2 asked for, but neither half has a case only it can refuse (zz-test/guard-needs-its-own-case). A later simplification of the condition passes the gate.
Consequences: each case needs a `pgrep` that works for one group and fails for the other. A stand-in on PATH can decide by its `-g` value against its own group: the stand-in runs from the launcher's backticks, so `perl -e 'print getpgrp'` in it is the launcher's group. It must answer only that exact form and `exec /usr/bin/pgrep "$@"` (Linux: `/usr/bin/pgrep` too, which the CI's Ubuntu has) for the side that works (zz-test/stand-ins-answer-only-named-arguments).
Recommendation: two spec cases under AC2, each with its own Rules and mutants row, run against M17 and M18:
- "a specs group pgrep fails to read is unread": the stand-in passes the launcher's own group to the real `pgrep` and exits 2 for any other `-g`. Expect `watchdog ?; group unread; reading: unread, no conclusion` and no `other process(es)`.
- "the launcher's own line not found is unread, even when the specs group reads": the stand-in exits 2 for the launcher's own group and passes the rest through. Expect the same, and no `watchdog gone`.
Lesson: zz-test/guard-needs-its-own-case

### F3 [low] AC1's "the jailed case ran" marker is never cleared, so an earlier run's marker vouches for a later one
Where: `check.sh` line 12 and `jailed_report()` (`-f .cache/c0132-jailed-ran`); spec line 212.
Evidence: after `./zn check c0132`, `z-nile/.cache/c0132-jailed-ran` is still there, in the clone and in `.worktree/proto-sweeper-report`. Nothing removes it before the spec runs, so a later run where the jailed case returned early (unjailed: an outer sandbox) passes AC1's jail requirement on the old file. Today AC7 would still fail such a run on macOS, so this only weakens AC1.
Critique: the marker exists to tell "checked jailed" from "skipped", and a stale file makes the two look the same (zz-test/no-vacuous-pass).
Consequences: none.
Recommendation: `rm -f .cache/c0132-jailed-ran` before `report_out=$(lune run tests/run …)` in check.sh.
Lesson: zz-test/no-vacuous-pass

### F4 [low] AC7 group-kills whatever number the fixture file holds, `1` included
Where: `check.sh` lines 96–98 (`[[ $g =~ ^[0-9]+$ ]]`, then `kill -KILL -- "-$g"`).
Evidence: the regex accepts `0` and `1`. `kill -KILL -- -1` signals every process the user owns (every session and gate on the machine), and `-0` signals the check's own group. Today only the fixture's probe writes the file, with its `getpgrp()`, so I found no input that produces either value.
Critique: this is a `-9` sent by a check outside the jail, to a target read from a file. A check that holds such a kill should confirm the target is its fixture.
Consequences: none.
Recommendation: require `g > 1`, and that `pgrep -g "$g"` lists a process whose command line names `$fx` (the fixture's runner) before the kill. Otherwise fail with the file's content.

Candidate lesson (for the lead): z-design: a round that adds a check.sh criterion or changes a spec waits for the prototype's CI (both gates) before the round is pushed, because the repository-wide scans (repo-fence, check-paths) judge check.sh and spec text, and `./zn check` never runs them. c0132 round 2 cited run 40448666640 as pending, and it failed both scans. Check: does every CI run the document cites have its result, and is it green for the commit the round reviews?

Verdict: changes
