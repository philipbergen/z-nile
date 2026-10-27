# Review 004: c0132 (design mode)
Inputs: prep head 19fe31c0 (`c0132.md`, `check.sh`, `acceptance/killed-report.spec.luau`, design-review-001 to 003, design-refute-001 to 003, `harvest.md`); prototype `proto-sweeper-report` at c0206f71 (its `check.sh` and both copies of the spec are byte-identical to the prep's: `cmp`), merged onto today's origin/main db7e812f in a scratch clone; zz-review, z-design, zz-test, zz-arch skills, `./zn lessons --when design`, zz-test/jail-reach-proved-by-a-real-run, zz-test/check-sh-judges-the-whole-spec-run, z-design/prototype-ci-green-before-the-round; `./zn capture c0132`; c0167 and c0168 on origin/main; the session's gate logs of the day's kills.
Dropped from review-003: F1 (fixed, verified below).

Verified by running (macOS, Lune 0.10.5, load about 37):
- In the clone (prototype merged onto origin/main): `./zn check c0132` 7/7, AC7's three real jailed runs included.
- **A case name removed from check.sh** (AC2's "the watchdog killed with the sweeper and the rest left: …"): `./zn check c0132` gave `1/7`: AC1 to AC6 each FAIL with `the spec's case "the watchdog killed with the sweeper and the rest left: read as neither group signal" is named by no criterion`; AC7 (which doesn't run the spec) passes. Restored afterwards.
- **M17** (` || ($x != 0 && $x != 1)` deleted from `fence.luau` 764) and **M18** (`!defined $me || ` deleted), each through `./zn check c0132`: `6/7`, AC2 FAIL on `:: a specs group pgrep fails to read is unread, even when the launcher's own line reads` and `:: the launcher's own line not found is unread, even when the specs group reads` respectively.
- **Names**: the spec's 18 `it("` names (extracted as `whole_run` does) against check.sh's 16 named lines: the only difference is `sets up` and `cleans up`. No named case is a prefix of another spec case (every pair checked: no hits).
- **`whole_run` against synthetic runner output** (its functions extracted from check.sh, fed `printf` lines):
  - an unnamed failing case: red;
  - a failing case whose name is a *prefix* of a named one ("the report says when"): red;
  - a failing case whose name *extends* a named one: `whole_run` green, but `report()`'s per-criterion `grep -F FAIL | grep -qF ":: <named>"` matches it, so the owning criterion is red;
  - `sets up` failing: red;
  - text glued to the end of a FAIL line: green in `whole_run` (the prefix rule), red in the owning criterion;
  - a FAIL line split before ` :: `: missed by both. No source of such a split exists today (F3).
  So a prefix can't fool it. Interleaving can fool it only by splitting a line, and nothing can split one today.
- **Regressions**: `lune run z-nile/affected` gives `ALL` for `fence.luau` and `zz-test/SKILL.md`. The promoted specs naming the three touched files (`grep -rlF`: c0120 layout and docs, c0076 sweeper, c0111 metrics-lessons and lessons-cli, c0127 skill, c0115 lessons and absence, c0081 skill-doc, repo-fence, c0114 gate-cover, c0058 fence, c0059 adapt), plus c0120 check-paths, c0077, c0078, c0079, fence-inherited-env, sweeper-interlock and the promoted c0132 spec: `182 passed, 0 failed, 20 spec files`. pickman `tests/meta/fence.spec.luau`: `10 passed`. Main's auto-merged `zz-test/SKILL.md` disturbs nothing.
- **Scope**: the capture asks "find what sends the SIGKILL … and make the runner tell the two apart". The finding half is c0167 by the recorded Scope decision. The two captured suspects are told apart by the pid-alone reading plus the memory figures, and by the Design's argument that a reused pid can't be the sweeper's. c0167 and c0168 exist on origin/main, and c0167's Problem quotes the readings.
- **Repository safety**: unchanged since review 003 (AC7's fixture under `z-nile/.cache/c0132-real`, the commit as `@example.invalid`, and the `-KILL` guard). `git status` was clean in the main checkout and the prep worktree before and after.

### F1 [low] The Problem doesn't list the fourth occurrence, and the cited logs live in a session scratchpad that will be deleted
Where: c0132.md Problem ("Second occurrence", "Third occurrence", "Both of the day's kills were printed right as z-nile's suite began"); Design, What prep found, **Timing** ("all three occurrences hit z-nile's suite").
Evidence: c0160's prep gate (`/private/tmp/claude-501/-Users-philipbergen-code-pickman/90b21ea5-d3e7-48bf-8ead-b2e9b8f802ce/scratchpad/c0160/gate-prep.log`, created 21:41:21, last written 21:44:01 on 2026-10-26):
```
== tests (full): pickman
1450 passed, 0 failed, 214 spec files

== tests (full): z-nile
tests/run: the jail's sweeper was killed (signal 9): processes the specs left may still run. Stop and report this.
```
Its retry (`gate-prep2.log`, 21:49:32 → 21:59:39) passed, with `1232 passed, 0 failed, 179 spec files` and `slowest: tests/acceptance/c0116/claims.spec.luau 400.5s, …`. The file times also date each kill:
- c0160's failing gate lasted 2 min 40 s in total;
- c0137's (`gate-c0137.log`, 15:43:40 → 15:47:51) lasted 4 min 11 s;
- a passing gate takes about 10 minutes, and its z-nile stage alone runs past 400 s.

The runner stops as soon as the sweeper dies. So each time, the sweeper died within the first minute or two of z-nile's suite, while the slowest-first schedule (main's `tests/lib/schedule.luau`) had its longest files in flight.
Critique: yes, the Problem should list it. The Problem may gain detail, and this is the same signature for the fourth time (three of them on one day), each time at the z-nile stage. The Design's Timing bullet counts "three", and "printed right as z-nile's suite began" can now be dated from the logs. Every log the Problem cites is under this session's `/private/tmp/.../scratchpad` or `tasks/`, and those folders go away with the session. Once they do, c0167 can't reread them.
Consequences: none for the design. The observe half (c0167) gets a dated datum to check the next report's `<secs>s after the specs started` against.
Recommendation: add a "Fourth occurrence (2026-10-26)" paragraph to the Problem: c0160's prep gate, pickman passed 1450/1450, the z-nile stage killed with signal 9, and the retry passed. Change "Both" to "All three of the day's kills" and the Timing bullet to "all four". Quote the gate lines and the file times into the document (or into c0167) rather than leaving only paths into a temporary scratchpad.

### F2 [low] OC1 and E8 promise "the spec files in flight", but the reading that points at a spec lists none
Where: c0132.md OC1 ("with the memory free and the spec files in flight"), Unknowns, "The sender itself stays unknown" ("its list names the spec files in flight"); Design table, the row with the watchdog alive and 0 others.
Evidence: the inside reading is, by definition, `watchdog alive; 0 other process(es)`: the spec's group signal killed every spec worker, so the list is empty. AC7's `inside` run shows exactly that. Only the pid-alone reading lists files.
Critique: the next occurrence, if it is the design's main suspect, arrives at c0167 with no spec named. OC1's wording suggests otherwise.
Consequences: naming the in-flight files in that case would take a new mechanism (the inner runner recording which files have started, and the launcher printing that record). That is new scope, which this round shouldn't add.
Recommendation: reword OC1 and the "sender stays unknown" sentence so the spec files are listed "when the specs still run (the pid-alone reading)". Add one line for c0167 (in its Problem, or in the skill's "Copy the whole report into c0167"): for the inside reading, narrow the spec by `<secs>` against the run's slowest-first schedule (`.cache` durations), as F1's times already suggest.

### F3 [low] `whole_run` assumes every failure prints one parseable `FAIL … :: <case>` line, and never checks that against the summary's count
Where: `check.sh` lines 24–27 (`grep -E "^FAIL .* :: "`) and 37 (any `[0-9]+ failed` accepted).
Evidence: synthetic output `FAIL x.spec.luau :sweeper: stopped 1` / `: an unnamed case` / `0 passed, 1 failed, 1 spec files` passes `whole_run` and every criterion's grep. Today nothing can produce it. One spec file runs in-process in `tests/run.luau`'s sequential loop, which prints each failure as one `print`, and the launcher's and sweeper's stderr come after Lune exits.
Critique: the guard rests on an output property it doesn't state. If the runner ever runs this file in a worker, or a case's child inherits stdout, it degrades silently.
Consequences: none beyond one comparison.
Recommendation: in `report()`, also require the summary's `<n> failed` to equal the number of `^FAIL .* :: ` lines (zero when every case passes); either way the criterion still names its own cases.

Verdict: approve
