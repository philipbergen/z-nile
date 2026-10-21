# Review 002: R0026 (code mode)
Inputs: HEAD 8269c6e (branch R0026-guard-follow-ups) against origin/main 7d8dee1 (`scripts/tracker.sh sync --fetch`, no merge); `git diff origin/main...HEAD`; fix delta `git diff 9826417..HEAD` (9826417 added review-001.md; fixes bf4b9c6 and a01eb38, then refute-001); review-001.md, refute-001.md; R0026.md (with "Addressed during execution"); c0074, c0076, c0077, c0078, c0079, c0080, c0096, c0097 documents, `check.sh` files and acceptance specs; stream-review-c0074-001.md, stream-review-c0080-001.md; the review, testing, tracker and architecture skills; execute-raft's Deviations and Stop conditions.
Dropped from review-001: F1, F2, F3, F4, F5 (each fix holds as code; F3's fix has a consequence of its own, F1 below)

Runs (macOS, outside any other sandbox; no "not jailed" note in either run, and the jailed cases ran, since RC0's c0076 and c0078 AC1 need their markers):
- `scripts/check.sh --full`: GATE PASSED, 1313 passed, 0 failed, 188 spec files; selene 0 errors, 0 parse errors; no `sweeper:` line.
- `bash tracker/rafts/active/R0026/check.sh`: 11/11 PASS (RC0 full gate, the 8 members, promote-check, RC1).
- No run printed `REPOSITORY CHANGED`. `git status` stayed clean.

Sequestration: `git diff --find-renames=100% --name-status origin/main...HEAD -- 'tracker/**/check.sh' 'tracker/**/acceptance/**'` lists R100 moves plus exactly what round 1 accepted (c0076's and c0078's one-line folder changes, c0096's and c0097's new `check.sh`); c0049's promoted spec change is c0097's. The fix delta touches no sequestered file. Not a violation.

How the round-1 fixes hold:
- Sweeper (F1): the ternary parses as intended (right-associative); the launcher form (`-`) is unaffected by the `PICKMAN_TEST_JAIL` rule, and the jail's root never has that variable yet (the bash line exports it later), as the refute says. The only unjailed processes that carry `PICKMAN_TEST_JAIL=sandbox-exec` are ones a person sets by hand. A set, unreadable seam now exits 70 before any candidate list is built. Off macOS the `$^O` refusal comes after the `-` form's parent-1 check, so c0076's orphan case still sees "no launcher above me".
- Remap base (F2): `sh.must` trims; under a spec run `TMPDIR` is the run's folder and the run's `mktemp` wrapper passes a template through; the user temp folder (and `/tmp`) are closed to specs, and the name is random, so no spec can plant anything there. The tripwire only lists worktrees under `.cache`. `fs.writeDir(".cache")` is still used elsewhere in `main.luau`, so its ALLOWED entry isn't stale.
- `fence.alive` / `fence.enter` (F3): the variable is set only for `outer sandbox …` verdicts, in the top Lune, before `takeLock`; the specs still get the runner's own export. In the nested "fixture of a guarded checkout" case the top Lune is inside the jail, where EPERM already meant "outside", so nothing changes there. Each spec file runs in its own Lune process, so the spec's temporary `process.env` edits can't race another file.

### F1 [medium] The F3 fix changes c0078's AC2 for outer-sandbox runs, unescalated and unrecorded: AC2 says a refused probe is "false … when unjailed", and an outer-sandbox run is unjailed
Where: `tests/lib/fence.luau:77-80` and `:655-658`; `tracker/issues/active/c0078/c0078.md:157` (AC2), `:50` (Design of `fence.alive`), `:37` (Non-goal), `:145` (Rules row); `tracker/issues/active/c0078/check.sh:35` (AC2's label: "alive counts a refused probe as alive only when jailed"); execute-raft Implementation step 5 ("wrong in a way that changes … an acceptance criterion: stop and escalate").
Evidence:
- AC2: "`fence.alive` is true for a live process it can't signal when jailed, false for one it can't signal when unjailed". The Design (line 50) says why: "Unjailed, a refusal means another user's or root's process … so it reads as dead and a stale lock naming a reused pid can still be taken over (design review 001 F8)."
- After a01eb38, a run accepted as `outer sandbox (protects the repository)` (`fence.luau:546`, printed as "note: not jailed") sets `PICKMAN_TEST_JAIL` to that verdict, and `fence.alive(<live pid it can't signal>)` returns true. So in that supported mode the code now does the opposite of AC2, and the design-review-001 F8 trade-off it encoded (stale lock taken over) is reversed (stale lock waits out the limit, then fails).
- The sequestered spec pins only `"sandbox-exec"` and `"none (unjailed)"` (jail-signals.spec lines 82-87), so AC2 still reads PASS. A Checked criterion that passes while its stated rule no longer holds in a supported mode.
- Nothing records the change: c0078's Verification log has no R0026-review entry, R0026.md's "Addressed during execution" lists only c0096 and c0097, and c0078's Non-goal (line 37, "An outer sandbox (Claude Code's own) allows them") still states the premise review 001 showed false.
Critique: the code is probably the right behaviour. Inside Claude Code's sandbox, a lock held by a run outside it (or in another sandbox instance) must read as alive, or two suites share one checkout, the 2026-09-30 failure. But the rule it changes is an acceptance criterion the user signed off at prep, and execute-raft says an AC change is a stop and escalate, not a reviewer-recommended edit. Round 1's Recommendation asked for it without flagging that (a code-mode Recommendation never asks for an AC or product decision), and the author followed it. The tempting fix, rewording c0078's Design and Non-goal to match the code, still leaves AC2 and its sequestered label contradicting the code with no decision on record.
Consequences:
- If the user accepts, AC2's text and the `check.sh` label stay as they are (sequestered). The decision must record that "unjailed" in AC2 now means "where signals aren't confined", and that an outer sandbox counts as confined.
- The stale-lock failure in that mode ("another test run (pid N) … gave up after Ns") doesn't say the pid may be a reused one or how to recover. The decision should say whether removing `.cache/tests-run.lock` by hand is the documented recovery (testing skill).
- If the user declines, reverting leaves the two-suites hazard inside an outer sandbox. It then belongs in the testing skill's "Caught only by review" list and c0078's Non-goals, with the false premise corrected.
Recommendation: escalate (execute-raft Stop conditions) with both options. Keep the code while waiting. On a decision:
- record it in R0026.md's "Addressed during execution" (or c0078's Verification log, as the tracker skill places it) with the user's words;
- correct c0078's Non-goal (line 37), Design (line 50) and Rules row (line 145) to the decided rule, and the testing skill's Signals bullet if needed;
- keep the new `sweeper-interlock.spec` case ("inside an outer sandbox, a refused liveness probe reads as alive") as the pin, and if accepted, add to it the recovery message (or a skill line) for the stale-lock case.
On the mechanism: this is the second round where a guard's documented rule and its code diverged by a reviewer-driven fix (round 1 F2 found the remap entry's stated reason false). Before answering `fixed`, check each fix against the issue's ACs and Rules table, and say in the `consequences:` which AC lines it touches.

### F2 [low] The round-1 fixes left c0076's and c0077's documents describing the old behaviour
Where: `tracker/issues/active/c0076/c0076.md:39` (step 4: "If env `PICKMAN_SWEEP_ONLY` names a readable file, only the pids listed"), `:67` ("narrowing-only"), Rules table (`:133-138`) and Verification log; `tracker/issues/active/c0077/c0077.md:210`.
Evidence:
- c0076 step 4 still implies an unreadable seam falls back to every pid. Its Rules table has no rows for the three refusals a01eb38 added (off macOS; an explicit pid without `PICKMAN_TEST_JAIL=sandbox-exec`; an unreadable seam). Review 001 F1's Recommendation asked for that table to be updated; the refute claims only the testing skill.
- c0077's Verification log still says the `.cache/tracker-remap-base` entry is listed "with the reason that git refuses to add a worktree over an existing path and that the top-level links are unlinked first". The entry is gone, and the reason was shown false.
- Neither issue's Verification log records the deviation (execute-raft step 5: "record the deviation, with the reason, in the issue's Verification log").
Critique: these documents are what the next reader (or a later raft's reviewer) checks the guards against. Round 1 F2 itself came from a false reason left in a reviewed list.
Consequences: none in code. The new Rules rows point at `tests/tooling/sweeper-interlock.spec.luau`, a non-sequestered spec, so they read "pinned outside the acceptance spec".
Recommendation: in c0076, fix step 4 and the narrowing line, add three Rules rows (rule, `sweeper-interlock ::` case, mutant, `run`: the refute says the spec was seen red first), and add a Verification-log line for R0026 review 001 F1. In c0077, add a Verification-log line saying the remap base moved to a fresh `mktemp -d` (review 001 F2) and that the line-210 reason no longer applies.

### F3 [low] `sweeper-interlock.spec`'s "unreadable seam" case can't fail outside the jail, and it doesn't check which refusal fired
Where: `tests/tooling/sweeper-interlock.spec.luau:68-72`, helper `refused` (`:45-51`).
Evidence: unjailed (an outer sandbox, or Linux), the case passes `outside = "1"` with no `PICKMAN_TEST_JAIL=sandbox-exec`. The sweeper then refuses with "an explicit pid outside a jailed spec run" (or "no jail on linux") before it reads the seam. A mutant that restores the old widening (`open(...) or` dropped back into the condition) still passes there. `refused` checks only "nothing swept", which every refusal prints. Jailed, the case is sound: the probe to the top process is refused, so only the seam rule can stop the sweep.
Critique: a case that runs green in a mode where it can't fail reads as coverage it isn't. The gate on a person's Mac is jailed, but an agent running the gate in an outer sandbox gets no signal from it.
Consequences: an early `return` when unjailed makes the case cover only the jailed run, like c0076's jailed cases. That's fine, since the jailed run is the one the sweeper exists for.
Recommendation: when not jailed, return early with a comment (as `sweeper.spec` does). When jailed, also expect `"test seam"` in stderr. Give the first case an `"explicit pid outside a jailed spec run"` (or, off macOS, `"no jail on"`) message check, so each refusal is pinned by its own reason.

## Judged criteria (code mode only)
None. No member of this raft has a Judged criterion.

Verdict: changes
