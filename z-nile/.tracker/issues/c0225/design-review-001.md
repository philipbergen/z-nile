# Review 001: c0225 (design mode)
Inputs: worktree `prep-sweeper-misses-exiting-leftovers` at 950607c97 with the uncommitted `c0225.md` (blob 0ab6144cd6), `check.sh` (290b08e53e), `acceptance/sweep-settle.spec.luau` (e7e19bb055) and `experiments/` (ref-patch.diff, E1 to E4, mutants.sh, mutants-result.txt, affected.txt); `./zn capture c0225` (d2623b6c8, no marker); `z-nile/tests/lib/fence.luau` (SWEEPER, REAPER, jail); `z-nile/tests/tooling/repo-fence.spec.luau`; `z-nile/engine/main.luau` (promote-check, withPromotedCopies); `z-nile/tests/slow.tsv`, `tests/lib/slow.luau`, `tests/lib/cachepaths.luau`; c0076's and the interlock's specs; c0168's stalled snapshot af1e1f9b9 (c0168.md, design-review-002.md); c0132's prep at origin/prep-sweeper-killed-under-load (aa60bfa2e) `killed-report.spec.luau`; the zz-review, zz-test and z-design skills; `./zn lessons` for sweeper, timing, guard, allow-list, repo-fence, promoted, seam, spinner.
Runs (read-only): `git apply --check experiments/ref-patch.diff`: applies to 950607c97. `stylua --check` and `selene` on the spec: clean. A case-insensitive grep of the spec and `check.sh` for every name in repo-fence's `NAMES`: the spec names `PICKMAN_TEST_FENCE` and `sandbox-exec`, `check.sh` none. `grep -rlF` over `z-nile/tests/acceptance` for `fence.luau`, `zz-test/SKILL.md` and `SWEEPER`, and a grep of those specs for `sweep`, `until nothing`, `keep appearing`, `passes:`: no promoted spec pins the passes or the Sweeper bullet's first sentences, so `Overrides: none` holds. No mutant was rerun; the machine was refusing forks for much of this session.

### F1 [high] Once promoted, the spec fails repo-fence's guard scan, and the design plans no allow-list entry
Where: `acceptance/sweep-settle.spec.luau:17` (`process.env.PICKMAN_TEST_JAIL == "sandbox-exec"`) and `:44` (`process.env.PICKMAN_TEST_FENCE`); `z-nile/tests/tooling/repo-fence.spec.luau:25-60` (`NAMES`), `:604-635` (the case "no spec, check.sh or script switches a guard off or points git elsewhere") and `:223-232` (c0076's and the interlock's entries for the same two names); in c0225.md: Touched modules, Implementation steps, Regression guard, and the Chore checklist's "Guards" line.
Evidence: `NAMES` lists `PICKMAN_TEST_FENCE` and `sandbox-exec`. The scan reads every `.luau` file of every home (`z-nile/` included; only the tracker roots are skipped). Specs prepared under a root are scanned only once they are promoted, so while the spec sits under `.tracker` the scan passes. That is why E5 saw no failure: it ran repo-fence on the prototype with the spec unpromoted. When `./zn done` copies the spec to `z-nile/tests/acceptance/c0225/sweep-settle.spec.luau`, the scan reports `... names PICKMAN_TEST_FENCE` and `... names sandbox-exec`, and every gate after that is red. `./zn promote-check c0225` (main.luau:4609-4661) runs only `luau-lsp` and `tests/meta/architecture.spec.luau`, so its OK proves nothing about this. The same thing happened to R0063: its `done` was rolled back because a promoted merge.spec had no ALLOWED key (lesson sources).
Critique: there are two tempting fixes, and both are wrong. Building the names from parts (`"sandbox" .. "-exec"`) hides a guard's name from the guard's own review. Putting the file on `EXEMPT` would also skip the identity scan (zz-test/narrow-guard-allowances).
Consequences: the ALLOWED key names a file that doesn't exist until `done`. The key-existence case (repo-fence.spec:637-669) accepts "an unfinished item's spec where done will promote it", so the entry can land on the raft's branch before `done`. The entry is an edit to a guard spec, which code review's item 8 reads, so the design has to state it in order to be reviewed against it. Any later edit that adds a banned name to the spec needs the dry-run again.
Recommendation: add an entry to repo-fence's `ALLOWED`, next to c0076's, with a comment naming c0225: key `z-nile/tests/acceptance/c0225/sweep-settle.spec.luau`, value `{ PICKMAN_TEST_FENCE = "reads the run's lock to find the top process, outside the jail", ["sandbox-exec"] = "tests whether it runs jailed" }`. Then update c0225.md:
- Add `z-nile/tests/tooling/repo-fence.spec.luau` to Touched modules.
- Add the entry to the Chore checklist's "Guards" line: two names, one file, neither set.
- Add an Implementation step after step 3: in a throwaway clone under `$TMPDIR`, copy the spec to its promoted place and run `tests/tooling/repo-fence.spec.luau`, which must be green apart from the known credential case. Then remove the entry and rerun: the scan case must go red. Record both results.
- Run the same dry-run in prep now, on the prototype clone, and add the result to E5.
Lesson: zz-test/dry-run-promoted-specs-under-the-guard-scan

### F2 [medium] AC4 compares the whole run's wall time with 0.2 s, so the no-pause mutant passes on a loaded machine
Where: spec `:166-176` (`took >= 0.2`); `sweep()` `:79-98`, whose timer covers the fork, the sweeper's Perl start-up, `sh -c`, the seam read and the ancestors' `pgrep`; the Rules and mutants row "empty scans are at least 50 ms apart" (M5, run once).
Evidence: the empty seam leaves no candidates, so under M5 the five scans cost microseconds and `took` is start-up time alone. E4 measured the whole unpatched sweep at 0.103 s median at load 13 to 14, and that figure includes a 25 ms full scan and the start of `sandbox-exec`. M5's AC4 case costs less than that, so its margin under the 0.2 s bar is about 0.1 s. The lesson's own measurements (a `./zn` call takes 0.3 s idle and 2.0 s at load 20) put start-up jitter at gate load above that margin, so M5 passes AC4 at gate load, and so does a mutant with a 10 ms pause (only 0.04 s of pauses). The correct implementation never fails this case, because each pause is a lower bound. The failure is a silent false pass, not a flake. Today's main passes AC4 too when the machine is slow enough.
Critique: the tempting fixes are a higher bar (0.25 s) or subtracting a baseline sweep. Both still compare process start-ups.
Consequences: a measurement inside the loop needs one observable event per scan. The only event the sweeper produces is the death of a process it found.
Recommendation: measure the gap between two kills inside the loop.
- Fixture: one watcher Perl process (in the sandbox, not in the seam, at most 30 s) forks two sleepers A and B and writes their pids. It `waitpid`s each and appends `<pid> <Time::HiRes::time>` to a file when each dies.
- Seam: `A@1 B@6`. Scan 1 stops A, scans 2 to 5 are empty, and scan 6 finds B.
- Expected gap from A's death to B's: at least 0.30 s for the design (the 50 ms pause after the kill, four 50 ms pauses after the empty scans, B's 50 ms re-probe). Under M5 it is about 0.10 s; with a 10 ms pause, about 0.14 s.
- Assert a gap of at least 0.25 s. Only `select` oversleeping can move a mutant toward the bar; start-up time can't.
- Rerun M1, M5 and a 10 ms-pause mutant several times while a gate is running, and record the results.

The case also confirms rule 2's restart.
Lesson: zz-test/timing-margins-above-jitter

### F3 [medium] No check runs the branch a real sweep takes (no seam), so a real sweep that stops nothing would pass every check
Where: `experiments/ref-patch.diff:58`, `(%from ? grep { $from{$_} <= $scan } @cand : @cand)`. Every `sweep()` in this spec and in c0076's spec (`:69`, `:115`, `:176`) sets `PICKMAN_SWEEP_ONLY`. The runner strips the seam from every real run (`fence.luau:686-688`).
Evidence: before this change the seam only reassigned `@cand`, so seamed specs ran the same scan line a real run does. With the patch, the scan line branches on `%from`, and the `: @cand` arm runs only with no seam. No spec can run that arm: an unseamed sweep inside a spec's jail would stop the other spec workers. So a wrong implementation passes all eight checks, for example:
- `grep { exists $from{$_} && $from{$_} <= $scan } @cand` with the ternary dropped as a "simplification": with no seam, a real run has no candidates and silently stops nothing;
- `++$quiet >= (%from ? 5 : 1)`.

E4 shows that the prototype's real path runs five scans, but E4 is an experiment, not a check.
Critique: when this guard fails, nothing turns red: leftovers outlive the run silently. The tempting fix is a check.sh-only real run with a leftover. It is worth adding, but it still can't see the five-scan count on the unseamed path.
Consequences: feeding hidden pids into `@cand`, instead of filtering `@cand` on every scan, changes where hidden pids are seen. The ancestors' map is built from `@cand` before the passes, so it has to cover the hidden entries too; otherwise a hidden pid that is an ancestor would not be kept.
Recommendation: keep the scan line exactly as it is today (`grep { !$keep{$_} && kill(0, $_) } @cand`) and let the seam feed it.
- Parse `%from` as the patch does (the last entry for a pid wins), then split it: entries with n = 1 go into `@cand`, entries with n > 1 into `%later`.
- At the top of each scan, move every `%later` entry whose n is at most `$scan` into `@cand`. With no seam `%later` is empty, so a real run executes only lines the seamed specs also execute.
- Build `@can` and `%keep` over `@cand` plus `keys %later`.
- Rerun M7 and M8 (M8 becomes "hidden entries pushed at scan 1") and the rest of the mutation set, and re-measure E4.

Also add a check.sh-only real run, like c0168's `real_run`: a fixture spec that leaves a detached sleeper (no spinner), run through the real `tests/run`, asserting `sweeper: stopped 1` and that the sleeper is gone.
Lesson candidate (for the lead): zz-test.
- Rule: a test seam feeds a guard's inputs and never adds a branch to the guarded path.
- Why: only the unseamed branch runs for real, and no spec can run it.
- Check: with the seam unset, does the code under test run an expression that no check executes?

### F4 [medium] AC5 puts a CPU spinner in the promoted suite, and its "gone" check rests on a single `kill -0`
Where: spec `:53-74` (`leave(..., true)` re-execs Perl without a pause for up to 30 s) and `:178-189`; `alive` and `waitGone` at `:27-40`.
Evidence: the looper burns a core from `leave()` until the sweep stops it (pid file, wrapper, sweeper start, re-probe: about 0.2 s), and for up to 30 s when a case fails before `stopping` takes its pid. The spec is promoted at `done` and runs in every gate that selects it. The design itself records that AC5 passes on today's main (750 of 750 sweeps in E2 and E3), so in the suite it guards nothing the seam cases don't. `waitGone` counts one failed `kill -0` as gone. That is the very shape this issue removes, applied to the one leftover whose probes the Problem says can miss.
Critique: the user's rule, recorded as the lesson below, is that a proof needing real work runs only from check.sh and is never promoted. The tempting fix, a pause in the looper, means it is no longer the captured mid-exec case, and it still burns CPU in every gate.
Consequences: a check.sh-only proof still needs a jail for the explicit-pid sweep. It runs only while the sequestered folder exists, that is, before `done`. Any file it adds under `acceptance/` is promoted and scanned at `done` (F1), unless check.sh only uses it in place.
Recommendation: move AC5's real exec-looper into a check.sh-only proof and keep AC5 Checked there.
- The proof has no `.spec.luau` name, sits under `acceptance/`, and runs only when `[ "$A" = "$HERE/acceptance" ]`, as in c0191's check.sh lines 18 and 27.
- Bound it with `ulimit -t 60` and `./zn run --time 120`, and run it jailed through a real `tests/run` (c0168's `real_run` shows the pattern).
- The promoted spec keeps only the seam cases, with sleepers and no spinner.
- In the proof, "gone" means five failed probes in a row, at least 50 ms apart, not one.
- Record the proof and its bounds in the design and in the script's header.
Lesson: zz-test/specs-never-burn-real-resources

### F5 [medium] Rule 3's "empty scans don't count toward the 50" has no row for its most likely wrong implementation: today's `for my $pass (1 .. 50)` kept, with empty scans spending passes
Where: The rule, step 3; the last row of Rules and mutants, which covers only "`last if ++$busy >= 50` dropped".
Evidence: an executor who edits today's loop as little as possible keeps `for my $pass (1 .. 50)` and adds `$quiet` with `next`. Every check still passes: the longest case, AC3, runs 12 scans. In a real run, ten stopping scans each followed by four empty ones reach pass 50 and exit 71 ("processes keep appearing") on a clean run. Ten stopping scans can come from a leftover tree or from a few foreign stragglers at load.
Critique: the table's reason for skipping a case (a 71 case costs 5 s) applies to dropping the busy cap. This mutant's case is cheaper, because it needs no zombie.
Consequences: a seam case pins it: ten sleepers at `@1 @6 @11 … @46`. The design ends with the command's status and `stopped 10` after 51 scans; the mutant exits 71 at pass 50. The case takes about 3 s, too slow for the promoted suite under the user's fast-gate rule but fine as a one-time check.sh line.
Recommendation: add the row (rule: "only stopping scans count toward the 50"; mutant: "the pass limit counts every scan"). Pin it with that check.sh-only case (sleepers, under `./zn run --time 60`), or record it as reasoned with this reason, and run the mutant.
Lesson candidate (for the lead): z-design.
- Rule: when a change splits a loop's iterations into kinds, every limit says which kinds it counts, and the table lists the mutant that counts the other kinds.
- Check: what did the old loop's bound become, and is its "counts every iteration" mutant listed?

### F6 [medium] The plan for merging with c0168 is wrong: c0168 also changes when the sweep ends, and its zombie rule contradicts "empty means nothing found"
Where: in c0225.md, the Chore checklist's "Existing work" (the c0168 sentence), Maintainability bullet 3 ("leaves the empty-scan count alone"), and Limits bullet 2.
Evidence:
- c0168's snapshot (af1e1f9b9, c0168.md rule 5) ends the sweep "on a pass that counts nothing and finds no pid the pass before did not find", so a zombie found in every pass, and never counted, still lets the sweep end with the command's status.
- Under c0225's rule as written, a scan that finds that zombie is not empty, five empty scans never come, and the sweep ends with 71 after 50 scans. That is c0168's own mutant M12 ("nothing ends the sweep but an empty find: 50 passes, 71"), which turns its AC2 and AC4 red.
- c0168's snapshot also leaves a note for c0225 at its line 125, "c0225 changes this end test and must carry both as a guard" (its Q1 is pinned only by its AC6 real run). c0225's design doesn't quote it.
- "Whichever lands second merges by hand, and its design must keep this issue's rule" doesn't say what "empty" means once a scan finds a process that is not counted.
- Limits says the restart "changes neither the run's status". That holds at the measured 1 busy scan in 120. But requiring five empty scans in a row turns sustained churn into a 71 where today one empty pass ends the sweep: P(71) ≈ (1 − (1 − f)^5)^50, about 0.017 a run at f = 0.4 busy scans per scan, against f^50 ≈ 0 today. c0168's end test is what removes that case.
Critique: whichever issue lands second finds this only when its own specs go red, and then has to invent the combined rule under pressure.
Consequences: the combined rule has to be stated now: "a scan is empty when, after the re-probe, it leaves nothing to stop. Once c0168 lands, a scan is empty when it counts nothing and finds no pid the scan before did not find. The sweep ends after five empty scans in a row, and any other scan sets the count to 0." Whichever lands second also carries the guard c0168 named, its forking-tree real run.
Recommendation:
- Replace Maintainability bullet 3 and the c0168 sentence with that combined rule.
- If c0168 lands first: say that c0225 takes c0168's end test as its definition of "empty" and carries c0168's AC6 real run.
- If c0225 lands first: say the same of c0168.
- Quote c0168's note.
- Correct the Limits claim with the churn bound above.
- c0168's documents can't be edited from here, so say how the rule reaches c0168's next prep: a note in its document on main through a capture, or a `depends_on` if the user prefers to fix the landing order.
Lesson: z-design/quote-other-preps-before-promising

### F7 [low] The experiments and the optional rerun don't name the bounded commands they ran with, and E1's looper has no lifeline
Where: Unknowns & experiments E2 to E5, and "Left for the executor"; the headers of `E2-sweep-looper.sh`, `E3-jailed-looper.luau`, `E4-sweep-cost.sh` and `mutants.sh`; `E1-probe-errno.pl`'s looper (`exec ... if getppid() == 1`).
Evidence: only E1's header names `./zn run --time 120`, and none of the design's E records names a command. "Rerunning E2 and E3 against the finished change is optional" tells the executor to run them with no bound. E1's looper calls `setpgrp`, which takes it out of the process group the wrapper kills, and it re-execs forever while orphaned. Only E1's last line stops it, so if E1 is killed earlier the looper keeps spinning, with no sweeper in a bare `sandbox-exec`.
Recommendation: record the exact `./zn run --time <s> -- …` command for each experiment, both in the design and in each script's header, and give E1's looper a deadline the way E2's has one (`time < $ARGV[1]`).
Lesson: z-design/instructions-runnable-where-they-run

### F8 [low] The seam still accepts `0` and zero-padded pids, so "it can only narrow a sweep" is not true
Where: `experiments/ref-patch.diff:43-44` (`/^(\d+)(?:@(\d+))?$/`); the Solution and "Why this fails closed".
Evidence: the entry `0` (or `0@3`) makes `kill(0, 0)` answer for the sweeper's own process group, and `kill 'STOP', 0` then stops the sweeper and the spec worker that started it, so the run hangs. The entry `007` is probed as pid 7 but keyed "007" in `%can`, so the ancestors' walk (`$can{$anc}` with the number 7) does not keep it. Both exist today (`^\d+$`), but this design rewrites the parse and claims the narrowing.
Recommendation: use `^([1-9]\d*)(?:@([1-9]\d*))?$` and convert with `0 + $1` before use, and qualify the claim to match. Don't add `0` to AC6's list, because on a mutant it would hang the case; give that row a reasoned entry instead.

Notes (no finding):
- Scope: the capture is confirmed (d2623b6c8, no marker). The title and Problem are unchanged. The captured outcome (a mid-exec leftover does not outlive the run) has a Design, Checked AC1 (the seam) and AC5 (a real process). The Limits name the window this rule can't see, which states a limit rather than cutting scope.
- c0132: its `killed-report` case (aa60bfa2e, `:294-316`) pins only its own phrases in the one-line Sweeper bullet, so this design's edit is compatible with it.
- c0076's sweeper spec is in the slow tier (`tests/slow.tsv:58`), so no affected or full gate runs it. AC8 runs it by name, as z-design/guards-name-slow-tier-specs asks.
- The `cachepaths` scan skips `z-nile/tests` and the tracker documents, so the spec's and check.sh's `.cache` lines need no entry there.
- The Perl rule otherwise matches today's exits: the command's status, 70 and 71; 50 stopping scans still give 71; `%gone` deduplicates. The re-probe that drops a just-exited process now counts as an empty scan, so a child forked before a STOP is looked for at least five more times. That part of the fail-closed argument holds.

Verdict: changes
