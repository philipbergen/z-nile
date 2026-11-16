# Review 001: c0132 (design mode)
Inputs: prep head b6828ed5 (`c0132.md`, `check.sh`, `acceptance/killed-report.spec.luau`); prototype `proto-sweeper-report` at 5c622209 (base c809181f); today's origin/main 299ce9b7; zz-review, z-design, zz-test, zz-arch skills and `./zn lessons --when design`.

Verified by running (macOS, jailed, Lune 0.10.5, loads 4 to 46):
- the prototype's spec with c0076 `sweeper`, c0077 `replace-file`, c0079 `watchdog` and `fence-inherited-env`: `51 passed, 0 failed, 5 spec files`; the 13 cases are the spec's 11 named cases plus set-up and clean-up.
- the prototype applied to today's origin/main (R0055's b029998e has changed `tests/run.luau` and the zz-test skill since the prototype's base) in a scratch clone, with the same specs plus c0078 `jail-signals`, `sweeper-interlock` and `fence-leftovers`: `65 passed, 0 failed, 8 spec files`.
- `./zn check c0132` at b6828ed5: `5 passed, 8 failed`, 1/6 criteria (AC4) passing, every failure an assertion, as Implementation step 1 says.
- CI 40424199358 (aef634f9) and 40432496485 (5c622209), branch `proto-sweeper-report`: both `success`; gate (z-nile) `1234 passed, 0 failed, 178 spec files` and `1235 passed, 0 failed, 178 spec files`.
- Mutants: M1 (the group killed before the report) spot-run, and it fails on an assertion in "the watchdog is alive and every process still in the group is listed". The other rows read as plausible and their cases fail on them.
- Repository safety: the spec writes only `<home>/.cache/c0132-report`; its nested launchers get no `PICKMAN_REAP_CACHE` (the runner unsets it), so their unlink step does nothing; the report only reads (`pgrep`, `sysctl`, `kill 0`). check.sh runs one spec through the runner and writes nothing. I found no path to the real repository.

### F1 [high] A whole-group signal sent from inside the jail leaves the watchdog alive, so the report and the skill read the design's main inside suspect as "only the sweeper's pid was signalled"
Where: c0132.md Solution ("a signal to the whole group (a `kill 0` from a member, or `kill -<group>` from anywhere) leaves nothing, the watchdog included"); Design, What prep found, second bullet ("a `kill 0` … from any spec process in that group kills the sweeper, the watchdog and every spec at once"); the zz-test Sweeper bullet text in the Design; AC2, AC6; `killed-report.spec.luau` "a whole group killed".
Evidence: the watchdog is forked in the launcher's child *before* it execs `sandbox-exec`, so it is in the specs' group but outside the jail. The jail's own rule says the same thing (`fence.luau` profile comment: a spec can signal "only processes of its own sandbox, never the runner's top process, the launcher or its watchdog"). I ran the prototype end to end in a scratch clone (`$TMPDIR/…/c0132rev/clone`), with a scratch spec in a real jailed run:
- the spec runs `kill "KILL", -getpgrp()` (the whole group, from inside): `watchdog alive (pid 25820); 0 other process(es) still in the group`. 8 more runs gave the same result, 8/8.
- the spec runs `kill "KILL", getpgrp()` (the sweeper's pid alone): `watchdog alive (pid 96883); 10 other process(es) still in the group:`, with the spec files in flight listed.
- from outside, `kill -KILL -- -<group>`: `watchdog gone; 0 other process(es) still in the group`.
- from outside, `kill -KILL <sweeper pid>`: `watchdog alive (pid 75632); 5 other process(es) …`.
So there are three signatures, not two. The documented reading ("`watchdog gone` with nothing left means the whole group was signalled (a `kill 0` or `kill -<group>`, from a spec or from outside the jail)") is wrong for a spec. A spec's `kill 0`, the very suspect "What prep found" singles out, prints `watchdog alive`, which the skill tells the reader means "only the sweeper's pid was signalled". The spec's "a whole group killed" case passes only because its stand-in runs the launcher, watchdog and `sh` all in the spec's one sandbox, which is not the real run's topology. AC6 then pins the wrong wording into the skill.
Critique: the issue exists to tell the senders apart, and as documented it misattributes the one inside sender it names. The tempting fix is to drop "a `kill 0` from a member" from the "gone" reading. That leaves the in-jail group kill without any reading, and its case still untested.
Consequences: the report gains a third reading. A pid-only signal always leaves the in-jail `bash`/`lune` top listed (it survives the sweeper), so "watchdog alive, 0 others" is distinct from "watchdog alive, N others". But a spec can't reproduce the real topology: `sandbox-exec` can't nest (`sandbox_apply: Operation not permitted`, exit 71, run here), so a spec stand-in can't put the watchdog outside the sweeper's sandbox.
Recommendation: correct the Solution, What prep found, the skill text and AC2/AC6 to the three readings:
- `watchdog alive` with processes listed: the sweeper's pid alone (a spec, the OS, or outside; the memory figures separate the OS);
- `watchdog alive` with nothing left: the whole group, signalled from inside the jail (a spec);
- `watchdog gone` with nothing left: the whole group, signalled from outside.
Consider having the who line state the reading in words, which Usability already claims it does ("the who line says, in words, which of the two readings applies"). It doesn't today: it prints only the facts. Record this run as a new experiment (E8). Because no spec can build the topology, pin the inside reading with a **check.sh AC** rather than a spec case. check.sh runs unjailed, so it can launch a real jailed run in a fixture clone under `.cache/<unique>` with no remote, where scratch specs signal the group (`kill KILL, -getpgrp()`) and the sweeper's pid (`kill KILL, getpgrp()`). The AC asserts the three signatures, with the outside group kill sent by the check itself to the fixture's recorded group. It runs at check and `done`, which is when this reading has to be shown true. Add a Rules and mutants row for it (mutant: the watchdog searched by a pattern that misses it, or the reading text swapped). Keep the existing in-sandbox case as the outside-kill model and rename it to say so.

### F2 [medium] A `pgrep` that can't run turns the report into the "whole group signalled from outside" signature
Where: Design, `fence.REAPER` step 2 (the `$me` and group lines); Chore checklist "Guards" ("whatever the report finds or fails to read").
Evidence: with the prototype's REAPER and `PATH=/nonexistent` (absolute `/usr/bin/perl` and `/bin/sh`), `sh -c '/bin/sleep 5 & /bin/sleep 0.3; kill -KILL $$'` reports `memory ?% free, swap used ?; …; watchdog gone; 0 other process(es) still in the group`. The same command with `pgrep` reachable reports `watchdog alive (pid 81557); 1 other process(es) … 81585 sleep 5`. Backticks also return nothing when `fork` fails (EAGAIN at the user's process limit), which is likely in exactly the load the issue describes (about 220 runner processes from parallel gates). An unread group is printed as an empty one.
Critique: the memory fields print `?` when unread (good, and specced), but the group fields don't. The one failure the report can't avoid reads as a confident diagnosis. The tempting fix is "check `$?`". But `pgrep` exits 1 for "no match", which is the honest result for an empty specs group.
Consequences: the launcher's own group always contains the launcher, so an empty `$me` lookup is always a failure to read, never "no match". An unread specs group (`$?` not 0 or 1, or -1 for a failed fork) needs its own token.
Recommendation: when `$me` is empty, or the specs-group `pgrep` returns `$?` other than 0 or 1, print `watchdog ?` and `group unread` (no count) instead of `gone` and `0`. Document `?` in the skill's readings as "unread: no conclusion". Add a spec case that runs the launcher with a PATH lacking `pgrep` (absolute `perl` and `sh`, as above) and expects `watchdog ?` and no `0 other`. Add its Rules and mutants row (mutant: an unread group printed as empty).

### F3 [medium] The "observe" half has no home: OC1 and the skill send the next report to an issue that won't take it
Where: Solution ("the next occurrence's report goes into this issue's follow-up"); OC1 ("recorded on this issue's follow-up"); the skill text ("Copy the whole report into the issue that tracks it (c0132)"); Non-goals third bullet ("fixing the count is a follow-up of its own").
Evidence: no follow-up exists. `git grep -lniE "sweeper|sweep.*count|dying process|exiting process" origin/main -- 'z-nile/.tracker/issues/*.md' ':!z-nile/.tracker/issues/done'` lists c0075, c0132, c0135 and c0156. c0075 is the unjailed runs, c0135 cites c0132 only as a duplicate-slug example, and c0156 is whole-file pins. Once c0132 is `done`, its document is frozen ("done items' documents stay as they were", Restated rules), so the skill's instruction points at a closed item, and OC1 names a follow-up nobody has captured. E7's count fix is in the same state.
Critique: the user decided "report then observe". With the report shipped and nowhere to observe into, the next occurrence's report is lost in a session log, which is how the first three occurrences went.
Consequences: a follow-up issue needs an id before AC6 pins the skill's wording, and the skill's sentence changes with it.
Recommendation: capture the follow-up now through z-ticket (for example "Sweeper killer: read the next report", carrying OC1 and the readings) and the E7 count issue. Name both ids in the Solution, OC1 and Non-goals, and point the skill's sentence at the follow-up's id. AC6's spec case should require that id in the bullet.

### F4 [low] The user's "report then observe" decision is not recorded as a Scope decision line
Where: c0132.md Problem.
Evidence: `grep -n "Scope decision\|Decided with" c0132.md` prints nothing. The capture (`./zn capture c0132`) asks to "Find what sends the SIGKILL … and make the runner tell the two apart". The design delivers the instrument and moves finding the sender to Observed OC1, on the user's 2026-10-26 decision, which the document doesn't quote.
Critique: without the line, a later reviewer or `done` reads OC1 as an unauthorised narrowing (z-design, Scope is what was captured).
Consequences: none.
Recommendation: add `Scope decision (user, 2026-10-26): "Yes, report then observe"` to the Problem, with a sentence saying that finding the sender is confirmed by OC1 from the next occurrence's report.

### F5 [low] The top process's `EPERM` branch has no row, and its mutant survives
Where: Design step 2 (`alive` when `kill(0, $top)` "succeeds or fails with `EPERM`"); Rules and mutants.
Evidence: removing `|| $!{EPERM}` from the prototype's REAPER leaves the spec at `13 passed, 0 failed` (run). In every case the spec's nested launcher shares the spec's sandbox with its top process, so the probe never meets `EPERM`.
Critique: either the branch is needed (a jailed launcher whose top process is outside the jail) and unpinned, or it is dead.
Consequences: none beyond one case.
Recommendation: add a case that runs the launcher with `top` set to the run's top process from `$PICKMAN_TEST_FENCE/.cache/tests-run.lock/pid` when jailed (as c0078's `outsidePid()` does; skipped when not jailed) and expects `alive`. Add its row (mutant: `EPERM` read as `gone`). Otherwise drop the branch from the Design.

### F6 [low] check.sh's failure detail prints the next case's failure under the wrong criterion
Where: `check.sh`, `report()`: `grep -F -A3 ":: $c" <<<"$report_out"`.
Evidence: in `./zn check c0132` at b6828ed5, AC2's detail lists "the report gives the memory the OS saw …" (an AC3 case), and AC5's lists "the testing skill says …" (AC6's). `-A3` runs past the failing case's own two lines.
Critique: a red check names a case it doesn't own, which misleads the executor.
Consequences: none.
Recommendation: print only the case's FAIL line and the line after it (`grep -F -A1`), or stop at the next `FAIL` line.

Candidate lesson (for the lead): zz-review or z-design: a design that says which processes a signal reaches checks each process's sandbox and group, not only its group, because c0132's design read the watchdog as reachable by a spec's `kill 0` when the jail's own profile comment says it isn't. Check: for each process the reading names, is it inside the jail, and does an end-to-end jailed run show the reading?

Verdict: changes
