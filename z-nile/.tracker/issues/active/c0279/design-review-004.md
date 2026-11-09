# Review 004: c0279 (design mode)
Inputs: prep `prep-dispatch-stop-spec` at 9877d342 (c0279.md, check.sh, acceptance/pins.sh, acceptance/fakecli-modes.expected, acceptance/dispatch-cli.spec.expected.diff, experiments/*.txt, harvest.md, spend.md, design-review-001..003 and design-refute-001..003, the lesson edits in 0d840424); prototype `proto-c0279` at 3cebeda3 (`git diff 1808a041 proto-c0279`, and `git diff 3e3648ad proto-c0279`); the author's run scripts and raw outputs in the session scratchpad (`loop4.sh`, `mut4.sh`, `r4/`, `mutd-M10-*`, `mutd-M7-*`, `mutd-M2-*`, `check4.txt`); z-nile/engine/runner.luau (the run loop, lines 150-290); tests/lib/fakecli.luau; the stall limits of control-cli.spec.luau and tests/tooling/dispatch-guards.spec.luau; `./zn capture c0279` (e88f68b6, no marker); PR #274; `./zn lessons --skill zz-review`, `./zn lessons --when design`. Probes, all read-only and through `./zn run` where they ran a program: pins.sh on 3cebeda3 (exit 0) and on main's files (exit 1, 20 lines); AC3's blob and golden recomputed; stylua and selene on the two prototype files (clean); `./zn lessons --uncovered c0279` and `--check` (ok); `git ls-remote origin main` (cd26b591, the spec's blob still 4fec0246). No spec run (machine load, and the brief). The background `./zn check c0279` on 3cebeda3 finished 3 of 3 (`check4.txt` in the scratchpad).
Dropped from design-review-003: F1 (M8 rebuilt with unique-pattern edits; M8 fails `stalled`, M8b passes; rows split), F2 (the user decided: "Widen them to 10 s"), F3 (the constants it named are fixed; new staleness is F5 here), F4 (rows added, `experiments/pins-wrong-fakes.txt`), F5 (spend rows 2 to 7 recorded), F6 (the pid-reuse false red is named in the Design).

### F1 [medium] The tool case's new 12 s quiet has no Rules row, and no mutant shows the case still proves the tool limit (2 s over the stall limit, the size of a starve this issue documents)
Where: Design, Changes (e) ("over c0040's 10 s stall limit and under its 30 s tool limit"); Rules and mutants, last row; chore checklist ("The spec still pins what it did"); E8.
Evidence:
- The case `a tool call quiet past the stall limit is not killed before the tool limit` passes on any correct dispatcher. It proves its rule only when the quiet tool call outlasts c0040's stall limit, so that a dispatcher that ignored the tool limit would stall the step.
- No Rules row states this, and no mutant tests it. The last row's mutants are M10 (c0040 back to 2 s) and M7 (closer dropped). M10 fails the tool case because the 3 s preamble delay goes past a 2 s limit before the first line, not because of the tool limit. M7 leaves the case green.
- The mutant that tests the rule is `runner.luau:236` → `local limit = r.stallSeconds` (the tool limit ignored). Read from the code, at idle:
  - `quiet` resets when the `tool_use` chunk is read (`:162`) and grows by `dt` per tick (`:200`).
  - It reaches 10 s two seconds before the `tool_result`, so the step is `stalled` and spec:690 fails `expected true, got false`.
- The margin is 2 s (12 - 10). The mutant survives a run in which the `tool_use` line is read more than about 2 s after it was written while the `tool_result` is read on time, because the reset happens late. `experiments/unfixed-run-B.txt` records a 2 s starve. That is never a false red, only a run that cannot see the regression.
- The fixture side is covered: a quiet shortened under 10 s is killed by AC1's exact `tool:` text.

Critique: this is the one rule the user's decision added to the design ("the tool fake's quiet call is 12 s"), and the chore claims the spec still pins what it did. The record shows only that the case passes, not that it can still fail. The tempting answer is to mark a row `reasoned` with "12 > 10". That hides the margin, and this issue exists because margins of this size get eaten.

Consequences:
- A row, and one run of a whole-file mutant (about 3 to 6 minutes under load).
- If the author wants a margin load cannot eat, a longer quiet costs time per run. For example, 20 s gives 10 s each side (under 30) and costs +8 s beyond the +33 s the user approved, so it is the user's call.

Recommendation:
- Add the row: "the tool case's quiet call outlasts c0040's stall limit and stays under its tool limit, so the case still proves the tool limit" | dispatch-cli :: a tool call quiet past the stall limit... | (a) the runner ignores `tool_seconds` (`runner.luau:236` → `r.stallSeconds`): `stalled`, spec:690 `expected true, got false`; (b) the quiet under the stall limit (`sleep 9`): AC1's `tool:` text | `run` for (a) at FAKE_DELAY unset, with an edit that asserts its pattern occurs exactly once and a read-back in the fixture's seed copy.
- State the 2 s margin, and that a loaded run may miss mutant (a) but never turns red.
- Keep 12 s unless the user picks a longer quiet with its cost.

Lesson: z-design/spec-design-correspondence

### F2 [medium] The preamble reaches every user of the fake, but Existing work, E6 and the Regression guard still say their modes are untouched, and no run of those specs uses the final fakecli
Where: Design, chore checklist "Existing work" ("the fake's other modes are untouched (E6)"); E6 ("the final prototype changes only the `stop`, `cap` and `push` modes, which none of them use"); Regression guard ("Existing specs at risk: … (the fake's users; their modes are untouched)"); proto `tests/lib/fakecli.luau:41`.
Evidence:
- 3cebeda3 makes `sleep ${FAKE_DELAY:-0}` the second line of every fake script that `fakecli.script()` writes. Every mode of every user runs it.
- Those users include control-cli.spec.luau (`stall_seconds = 3`, and closers at 8 s and 10 s) and tests/tooling/dispatch-guards.spec.luau (`stall_seconds = 3`). With FAKE_DELAY unset, each fake now forks and execs `/bin/sleep 0` before its first line, inside a 3 s silence window.
- control-cli is the file c0287 was captured for (load sensitive, 905 s under load).
- The only run of those three specs is `experiments/draft1-other-fakecli-users.txt` (41 passed). That ran on draft 1, whose first line was an `echo` of a system line: an output at once, which is the opposite of a delay before the first output.
- 3cebeda3 also changes the `tool` mode. Only dispatch-cli uses it (`grep` of `mode(` across tests), so that part of the claim survives.
- Effect: small, about one process start (the E1b probe timed the whole pipeline at 0.04 s at load 97). But it pushes in the wrong direction in exactly the files c0287 must make load-proof, and the record denies it exists.

Critique: the Regression guard is where a raft reviewer and c0287's designer look to learn what this change reaches. The tempting fix is to correct the sentence only. That still leaves an unmeasured change in the 3 s windows of two other promoted specs, for a delay that only `check.sh` ever sets.

Consequences:
- A preamble that spawns nothing when the variable is unset makes the other users' fakes run exactly what main runs: `[ -z "${FAKE_DELAY:-}" ] || sleep "$FAKE_DELAY"` (`[` is a builtin of `sh`).
- That changes pins.sh's first-line pin, which should then match the exact line (F6), and Changes (d).
- The stop and push delays run only in dispatch-cli and can stay as they are.
- c0287 will touch control-cli, and probably fakecli's `orphan` mode. Name it, so the two designs agree on the preamble.

Recommendation:
- Either guard the preamble as above, pin its exact line, and rerun AC2 once.
- Or keep `sleep ${FAKE_DELAY:-0}`, and run control-cli, dispatch-guards and repo-fence once on the final fakecli (save the log in experiments/).
- Either way, correct Existing work, E6 and the Regression guard: the preamble runs in every mode of every user, and the `tool` mode is dispatch-cli's alone. Name c0287 there and in E5.

Lesson: z-design/restated-rules-move-together

### F3 [medium] Answering round 3 rewrote c0194's lesson instead of adding a note: its source and half its rule are gone
Where: z-nile/skills/z-design/lessons/read-back-every-prototype-edit.md (commit 0d840424); harvest.md (design-review-003 F1).
Evidence:
- Before 0d840424 (from c0194's prep, d464c1af), the lesson's check read: "After each scripted edit of the prototype, was the changed place read back, or a spec case run that fails if the edit did not apply?" Its body described a replace that silently did not apply after the formatter reflowed its anchor. Its Why was c0194 prep and design review 001 F4. Its How to apply said: "assert the pattern is present …, read the lines back after, and give the behaviour a case that fails without the edit".
- 0d840424 replaced the title, tags, check, body, Why and How to apply wholesale. The new check asks only about "mutation edit[s]" and about a "surviving mutant".
  - A prototype edit that is not a mutant, which was c0194's own case, is no longer asked about.
  - So is an edit whose mutant dies for the wrong reason.
  - So is "a case that fails without the edit".
  - The Why now names only "c0279 design review 003 F1".
- c0194 is active (`issues/active/c0194/harvest.md:36,49` still points at this lesson as the one it created).
- zz-review's Lessons rule and z-design's: "It adds a note to an existing lesson when one fits, writes a new file only when none does".

Critique: the lesson base loses a rule that another raft learned, and every future prep is asked a narrower question. The tempting fix is to append c0194's Why under the new text. That restores the source but keeps the narrower check.

Consequences: none for c0279's design. If c0194's raft edits the same file, the change also conflicts with it.

Recommendation:
- Restore the c0194 version (`git show d464c1af:z-nile/skills/z-design/lessons/read-back-every-prototype-edit.md`). Widen its check to cover both cases: "After each scripted edit of the prototype or a mutant, did the edit refuse a pattern that does not occur exactly once, was the changed place read back in the copy that runs (the fixture's seed for a spec), and is there a case that fails without the edit? Was a surviving mutant read back before its survival was explained?"
- Add c0279's case as `**Also:** c0279 design review 003 F1: …`.

### F4 [low] The load argument, Non-goals and Scalability were not updated for the user's decision
Where: Design, "Why this holds under any load"; Non-goals bullet 2; Scalability; spec comment on line 174.
Evidence:
- "Why this holds under any load: no case waits for a clock to prove anything" is no longer true. The four c0040 sub-cases (wait, prose, stall, tool) wait for a 10 s limit by design, and they hold only up to a starve of that size.
  - False stall: 10 s before a step's first line is read, 7 s under AC2's 3 s preamble.
  - Missed stall: 10 s across the fakes' 20 s silence. If the runner misses the limit before the fake exits, `stall` ends `failed` and `wait` gets no quota. Before the change this side had 18 s (2 s limit, 20 s silence); now it has 10 s, and the record never states it.
- Non-goal 2 says "No new wall-clock wait, and none longer". The decision made four waits longer (2 s to 10 s, and 3 s to 12 s).
- Scalability says "No added cost in the common case". The decision costs about +33 s per run of the file, and E8 checks that sum correctly: 3 × 8 + 9 s.
  - AC2 now delays every fake start by 3 s. The run took 352 s, against 178 to 228 s for the undelayed runs of the same loop (`r4/` mtimes), so each `./zn check c0279` costs about 2.5 minutes more.
  - The user's option named only the +33 s.

Recommendation:
- Say that the c0040 sub-cases are the one exception, and name both margins and their AC2 values.
- Note that the silences of `wait`, `prose` and `stall` can be lengthened at no cost to a passing run, because the step is killed at the limit. For example, 40 s makes the missed-stall side 30 s. Those three modes are dispatch-cli's alone. Pin them in fakecli-modes.expected if they change.
- Carve the decision out of Non-goal 2, and give Scalability both costs.

Lesson: z-design/restated-rules-move-together

### F5 [low] Stale record and executor text after the change
Where: Implementation steps 0 and 1; Test plan AC1; Design Changes ("(75 lines)"); frontmatter `size`; check.sh's AC2 comment; pins.sh comment; E3, E4, E4b, E7, E8; Rules row 1.
Evidence:
- Step 0 re-preps only if main moves "the `stop`, `cap` or `push` modes". The `tool` entry and the preamble line are now pinned too.
- Step 1 says "(the three modes)". The change is four modes plus the preamble.
- Test plan AC1 says "the exact text of the `stop`, `cap` and `push` entries". pins.sh compares `stop cap push tool`, and its own comment says "the three entries".
- The golden diff is 84 lines, not 75 (`wc -l`).
- `size: 30`, but the prototype changes 50 lines (`git diff --numstat 1808a041 proto-c0279`: 24+12 and 10+4).
- check.sh's AC2 comment says only "the stop and the push wait 3 s". Every fake now does, before its first line.
- E4's M2 and M7 sentences, and E3's "the stop and the push cases fail", describe the earlier runs.
  - Their logs were deleted (`mutant-M2-old-stall-limit-with-delay.txt`) or replaced in place (`mutant-M7-no-c0040-closer.txt` → `mutant-M7-r4.txt`).
  - The files E4 points to ("logs experiments/mutant-*.txt") now show the r4 results: M2 has 17 failures, not 2.
- Rules row 1 still says "M2: stop and push cases `stalled`".
- E4b's "3 of 3 … the last run after the last prototype commit": when the prep commit was made (22:18:40), the check of 3cebeda3 had not finished (`check4.txt` at 22:18:53 held AC1 only). It has now passed 3 of 3, but its log is not in experiments/.
- E7 is called "final prototype", though it no longer is.
- E8 says "the final commit changes neither the stop nor the cap fake". The preamble runs in both. The conclusion that M1, M3, M4, M8 and M8b are unchanged holds by reading, because the delay comes before everything they exercise. Say that instead.
- The experiments do say honestly which commit each ran on: `mut4.sh` copies proto's 3cebeda3 files into the base worktree, `loop4.sh` runs in proto after 21:58:31, and the failing line numbers (659, 671, 690, 703, 717) match 3cebeda3.

Recommendation: correct each sentence. Save the 3 of 3 check output to experiments/. Mark E3 and E4's M2 and M7 sentences as runs on 13aca7c8 whose logs were replaced, or drop them in favour of E8.

Lesson: z-design/decided-guesses-rewrite-their-body

### F6 [low] The first-line pin accepts a preamble that delays nothing
Where: acceptance/pins.sh (`[[ $first == *'sleep ${FAKE_DELAY:-0}'* ]]`).
Evidence: a first command of `"sleep ${FAKE_DELAY:-0} &",` (backgrounded) or `"true; # sleep ${FAKE_DELAY:-0}",` passes the pin. AC2 still passes too, because c0040 is at 10 s. AC2 is then no longer a simulated starve before the first line, and the promoted spec is unchanged, so nothing else notices.
Recommendation: compare `$first` with the exact line (whatever form F2 settles on), the way fakecli-modes.expected pins the four entries.

### F7 [low] PR #274 still carries the pre-decision design marked ready and prepared
Where: PR #274 (head `prep-dispatch-stop-spec` on origin at da11f85f); frontmatter.
Evidence:
- Origin's prep branch is da11f85f. In it c0040 is at 2 s, there is no M10 and no Scope decision line, yet it has `design: ready` and `status: prepared-walrus-sunny-lucky`. 9877d342 is not pushed.
- Round 3's answers added Rules rows and experiments. That is more than minor, so under z-design step 5.4 round 3 was not final, and `ready` and `prepared` came before the final round.
Recommendation: don't merge #274 until the last round is answered and pushed. If the coordinator's tooling allows it, keep `design: reviewed` until then.

Checked without a finding:
- AC3, recomputed:
  - `git rev-parse proto-c0279:<spec>` and `git hash-object` in the proto worktree both give `28d078ba…`, the blob in check.sh and AC3.
  - The diff from the merge base (1808a041), less its index line, equals acceptance/dispatch-cli.spec.expected.diff byte for byte.
  - origin/main (cd26b591) still has blob `4fec0246…`. The only commit since 1808a041 under tests/lib, c0117's specs or the engine is c61cc96b (`tests/lib/cachepaths.luau`, 3 lines), which touches neither file.
- pins.sh:
  - Exit 0 on 3cebeda3. Exit 1 on main's files, with 20 MISSING, PRESENT or DIFFERS lines, the `tool` entry and the first-line pin among them.
  - The `mode tool` anchor `tool) ` first matches line 80 (`silenttool) ` is line 131, later).
  - The prep's acceptance/ and check.sh equal the copies in the proto worktree that the background check used.
- The numbers agree across the spec (root 120 s and 240 s; c0040 `[dispatch]\nstall_seconds = 10\ntool_seconds = 30\n`), the fakes (`wait`, `prose` and `stall` silent for 20 s after their line; `tool` quiet for 12 s), pins.sh, fakecli-modes.expected, AC1, Solution item 1, Changes (e), the Regression guard and E8.
- No case outside c0040 depended on the old 2 s limit. Every other mode dispatch-cli uses ends by its own signal at once: a `rate_limit_event` sets quota on read, the cap fires on tokens, and the others exit. `wait`, `prose`, `stall` and `tool` are used only by dispatch-cli.
- +33 s is honest for a run without the delay: 3 × (10 - 2) s plus (12 - 3) s, less the stop fake's removed 0.5 s.
- M10, M7 and M2 (r4) ran on 3cebeda3's files.
  - `mut4.sh` copies them and asserts each pattern occurs exactly once. The M7 edit blanks the line, so line numbers stay put.
  - Their failures sit at 3cebeda3's lines.
  - M10's result (the wait and tool cases fail under FAKE_DELAY=3) exists only with the preamble delay, so it could not have run on 3e3648ad.
  - E8's durations agree with the `r4/` file times: 352 s, then 228, 178, 195 and 204 s.
- FAKE_DELAY reaches the fakes: M10 and M2 fail as predicted under it.
- Repository safety: AC1 and AC3 only read. AC2 runs the spec under the runner's jail. `mut4.sh` restores the base worktree's files (`git checkout -- .`) and moves no ref. Every run in the scripts goes through `../zn run --time`.
- Scope: the capture (e88f68b6) has only gained `Scope decision` lines. The third one quotes the user's words and the option's text, and every captured outcome has a Design and a Checked criterion.
- stylua and selene are clean on both prototype files. `./zn lessons --uncovered c0279` and `--check` pass.

Lesson candidates (for the lead):
- z-design, a note on restated-rules-move-together: a user decision that changes constants late in prep invalidates the design's general claims ("under any load", "no added cost", "none longer", "their modes are untouched"), not only its numbers. Check: after a decision changes a value, did a grep for every claim the old value supported (the headline argument, Non-goals, Scalability, Regression guard, Implementation steps) find each one rewritten?
- zz-test, a new lesson or a note on fake-keepalive-must-not-end-the-step-itself: a test knob added to a shared fake (an env-driven delay) runs in every spec that uses the fake. Make it spawn nothing when unset, or run every user once. Check: does the knob add a process or an output to the fake's default path, and which other specs run that path inside a short silence window?

Verdict: changes
