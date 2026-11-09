# Review 003: c0279 (design mode)
Inputs: prep `prep-dispatch-stop-spec` at 7201c100 (c0279.md, check.sh, acceptance/pins.sh, acceptance/fakecli-modes.expected, acceptance/dispatch-cli.spec.expected.diff, experiments/*.txt, harvest.md, design-review-001/002.md, design-refute-001/002.md, the two lesson notes added in round 2); prototype `proto-c0279` at 3e3648ad (`git diff 1808a041 proto-c0279`, and each proto commit's stop/cap modes and limits); the M8b run's fixture left in `.worktree/proto-c0279-base/z-nile/.cache/c0117-dispatch/` (its seed engine and `main/.cache/dispatch/c0060/state.json`); the mutation and run scripts in the session scratchpad (`mutA.sh`, `final.sh`, `loop3.sh`, `r3/`); z-nile/engine/runner.luau (run loop, SUPERVISOR, killGroup), dispatcher.luau (stopAt, the step's env, the final `st.outcome`), tests/lib/fakecli.luau, trackerfix.luau, engine.luau (engine.copy/TOP); `./zn capture c0279` (e88f68b6, no marker); `./zn lessons --skill zz-review --full`, `./zn lessons --when design`. Probes, all through `./zn run`: pins.sh on 3e3648ad (exit 0) and on main (exit 1, 18 lines); AC3's blob and golden recomputed; stylua, selene and `luau-lsp analyze` on the final two files (clean); `./zn promote-check c0279` (OK); `./zn lessons --uncovered c0279` and `--check` (ok); a pid-rate probe (F6). No spec run (machine load).
Dropped from design-review-002: F2, F4, F5, F6 (fixed, verified below); F1 (the user's open decision: per the brief I judge only its record, in F2 here); F7 (fixed except what F3 and F5 here repeat).

### F1 [medium] The marker-only mutant M8 was mis-built: its survival, and the record's "another path … not located … no case could kill it", are wrong, and the silent hold after the stop still has no mutant that dies by it (repeat of design-review-002 F3)
Where: E4 (the M8 paragraph); Rules and mutants row 3; Solution item 2 ("… instead of an exit that would look like a stop (M1)"); design-refute-002 F3.
Evidence:
- The scripts that built M8 replace the first occurrence of a pattern. `mutA.sh` and `final.sh` (scratchpad) both run `s.replace(a, b, 1)` with `a = 'if fs.isFile(stopFile) then'`. In runner.luau that pattern first occurs at line 141, the pre-start check ("stopped by ./zn dispatch stop before it started"). The run loop's marker branch is the second occurrence, at line 237.
- The M8b run's fixture is still on disk. `diff z-nile/engine/runner.luau .worktree/proto-c0279-base/z-nile/.cache/c0117-dispatch/seed/z-nile/engine/runner.luau` prints only `141c141` (`if fs.isFile(stopFile) then` → `if false then`), and dispatcher.luau differs only at 1916 (`runner.killGroup(...)` → `local _ = 0`). Lines 237-238 (`early = "stopped"`) and 262-265 (the runner's `killGroup(pgid)`) are intact.
- The same fixture's `main/.cache/dispatch/c0060/state.json` records the stop attempt as `outcome "stopped", detail "stopped by ./zn dispatch stop", minutes 0`. The step ended right after the stop, nowhere near the 120 s stall: the run loop's marker branch ended it and killed the group. That is the "other path".
- What the intended mutant does, read from the code (not run: a run waits out the 120 s stall on top of the spec's minutes). With runner.luau:237-238 and dispatcher.luau:1916 removed:
  - stopAt writes the marker, saves `stopped` and returns, and the fake holds silently (`sleep 3600`).
  - The run loop reaches `quiet >= 120`, gives `stalled` and kills the group (:249, :265).
  - The dispatcher then saves `st.outcome = outcome` (`stalled`) over stopAt's `stopped`, and the case fails at spec:703 with `expected "stopped", got "stalled"`.
- The same mutant with the hold cut to `sleep 20` passes:
  - The fake exits 0 with no token count, so the step is `failed`.
  - runner.luau:286 maps failed plus the marker to `stopped`.
  - The supervisor's exit `group(15)` kills the grandchild.

  So the hold is exactly what kills the intended M8.
- M1 (the stop replaced by `true`) dies with the hold or without it: `stalled` with it, `failed` without it, because no marker is written. The author's own round-2 note in z-design/spec-design-correspondence says so. Yet refute-002 F3 says "Row 3 now names M1 …, the mutant that does die because of the hold's rule", and Solution item 2 still credits the hold to M1.
- Row 3's reason ("this issue does not test the dispatcher's stop (Non-goals)") contradicts the chore checklist ("The spec still pins what it did: stop kills the step's whole group"). Non-goal 1 forbids changing the dispatcher, not testing it.

Critique: the record now tells the user and the executor something false about the engine: a hidden kill path that no case can see. Meanwhile the rule round 2 asked about (the silent hold, which AC1 pins as `sleep 3600 ;;`) still has no mutant that dies because of it. The tempting answer is to reword the row as `reasoned` again, which would still rest on the mis-built run.

Consequences:
- The corrected mutant costs at least 120 s per run, the stall it waits for.
- Nothing in the promoted spec, pins.sh or the golden changes.
- The thing that broke is the mutation scripts' first-occurrence replace: any pattern that occurs twice edits its first occurrence, silently.

Recommendation:
- Make every mutation edit refuse a pattern that does not occur exactly once (`assert s.count(a) == 1`), or anchor it on the run loop's branch (`if fs.isFile(stopFile) then\n\t\t\tearly, detail = "stopped"`). Then read the edit back in the copy the spec runs: `.cache/c0117-dispatch/seed/z-nile/engine/`.
- Run the corrected M8 (runner.luau:237-238 and dispatcher.luau:1916 removed, `FAKE_DELAY=3`). It must fail at spec:703 with `expected "stopped", got "stalled"`.
- Run its pair (the same, plus `sleep 3600 ;;]]` → `sleep 20 ;;]]` in the stop fake). It must pass. Save both logs.
- Make the corrected M8 row 3's mutant, marked `run`. Keep M1 as its own row ("a stop that writes no marker"), and drop "(M1)" from Solution item 2.
- Replace E4's M8 paragraph and the "not located / no case could kill it" claim with what the fixture shows (refute-003 says so for refute-002 F3).
- The minimum, if the two runs stay out of reach: correct the record, and mark row 3 `reasoned`, with the code path above as its reason.

Lesson: z-design/read-back-every-prototype-edit, z-design/contradicting-results-are-unknowns

### F2 [medium] The open decision's record understates what the logs show: a 2 s starve was seen (run B), more windows are exposed than "before the first line", and the Problem still presents the coordinator's gloss as the user's words
Where: Non-goals, last bullet ("not seen in 8 runs"); E5; Problem, second `Scope decision` line.
Evidence:
- Non-goals says the stall cases "are load sensitive only if the dispatcher itself is starved for 2 s (not seen in 8 runs)". But experiments/unfixed-run-B.txt has `zz-review on claude: stalled (no output for 2 s), 0 tokens` in the quota fallthrough case, whose fake beats every 0.5 s, and E1b puts such a stall down to "the machine and the dispatcher".
  - So a starve of that length happened in 1 of the 8 unfixed runs. It hit another case's step.
  - What was not seen is a stall case failing: none failed in the 8 unfixed runs, the 6 fixed runs, the 5 final runs, or the mutant runs that leave c0040 alone.
- The starve is not only the dispatcher's. A fake whose start is starved before its first line counts the same way, because the runner charges every starved tick to the step (`quiet += dt`).
- E5's window ("before it reads their first line") misses two others:
  - In the wait sub-case, the grok fallback step runs whole under c0040's 2 s limit (spawn, preamble, its two lines).
  - In the tool case, the limit drops back to 2 s after the tool_result line.
- The Problem still reads `Scope decision (user, 2026-11-08): "Yes, every load-sensitive case in that file": c0279 covers every case … that the load runs show failing …`. The Non-goal says the text after the colon is the coordinator's, but the Problem itself does not, so a reader of the Problem alone takes the narrowing as the user's.

Critique: the user decides between (i), (ii) and (iii) from this paragraph, and "not seen" leans towards (ii) on a premise the logs contradict. The options themselves are complete and correctly costed. I checked (i)'s +33 s: the prose and stall sub-cases +8 s each, the wait sub-case +8 s, and the tool fake's quiet going from 3 s to 12 s +9 s. Option (iii) is honestly marked as outside the capture.

Consequences: wording only. The decision stays open, and `design: ready` waits for the user's line (z-design step 5: "Anything else goes to the user before `design: ready`").

Recommendation:
- Reword the Non-goal and E5: "a starve of 2 s or more stalled a step in 1 of 8 unfixed runs (run B, in another case). The stall cases' exposed windows did not fail in any of N runs: claude's spawn to first line in the wait and tool sub-cases, the wait sub-case's whole grok step, and the tool case after its result line." Say the starve can be the fake's or the dispatcher's.
- In the Problem, mark the text after the colon as the coordinator's reading pending the user, or move it into the Non-goal.
- Say that `ready` waits for the user's answer.

Lesson: z-design/never-narrow-captured-scope

### F3 [low] Stale constants and claims from earlier rounds
Where: Regression guard; Test plan; Design; E1; E4b; E7; pins.sh.
Evidence:
- Regression guard: "root stall 60 s and tool 120 s". It is 120 s and 240 s.
- Test plan, AC1: "root stall 60 s". It is 120 s.
- Design: "(71 lines)". The golden diff is 75 lines (`wc -l`).
- Design, "Why this holds": "The 120 s stall limit cannot be reached by a fake that is slow, only by one that is stuck." This is a bound, as review 002 F7 said of the 60 s sentence.
- Scalability names only the 60 s kill bound. A stop that kills nothing now also costs the 120 s stall, where it used to cost 2 s.
- E1: "its log is the check output, not a file". The log is now experiments/unfixed-check-ac2-push-failure.txt, a run of round 1's check.sh in the prep worktree.
- E4b: "on the unfixed worktree … AC2 passes". The one saved unfixed check shows AC2 failing (the push case, under load), so before the fix AC2 passes or fails depending on load.
- E4b's final 3 of 3 has no log. I re-ran AC1 (pins.sh) and AC3's two commands on 3e3648ad, exit 0 each. AC2's evidence is final-delay3.txt.
- E7 says of `sweeper: stopped 1 process(es)` (final-delay3.txt): "so it is not the fix's". It is unexplained and also occurs before the fix; say that rather than ruling it out.
- pins.sh says "the exact text (comments included)", but `mode()` reads from the `name) ` line to `;;`, so the comment lines above each entry are not pinned.

Recommendation: correct each sentence. No rule changes.

### F4 [low] Three Design rules that only the text pins kill have no Rules rows, and round 2's three wrong fakes have neither a row nor a log
Where: Rules and mutants; design-refute-002 F4; Test plan AC1.
Evidence:
- Three rules from the Design's "Why this holds" have no rows:
  - The poll is bounded on the wall clock. Its mutant (back to the summed `task.wait` bound) is killed only by AC3.
  - The grandchild outlives any wait. Its mutant (`exec sleep 120`) is killed by AC1's `exec sleep 3600` pin.
  - The fake waits for the pid file before acting. Its mutant (no wait) is killed by AC1's exact text.
- refute-002 F4 says the three wrong fakes all fail AC1 (a delay after the stop, a `while true` heartbeat, the wrong `$$`). experiments/ has no log of that run and the table has no rows for them, although review 002 F4 asked for rows.

Recommendation: add the rows with `AC1`/`AC3 (text pins)` as their case, and save one log of the three wrong fakes run against pins.sh. pins.sh only reads, so this costs seconds.

### F5 [low] Spend rows and the `reviewed` mark are still deferred (repeat of design-review-002 F7)
Where: spend.md; frontmatter; design-refute-002 F7.
Evidence:
- origin/main's `z-nile/.tracker/issues/c0279/spend.md` holds only the capture row. z-design step 5.2 records the reviewer's spend "as soon as a subagent reviewer returns", and step 5.3 records the refute's spend "once the round is answered".
- The frontmatter says `design: draft`. Step 5.1 marks `design: reviewed` after the lessons pass, before round 1. Refute-002 F7's "set when the final round is done" reads step 5.1 backwards.

Recommendation: record the rows for rounds 1 to 3 (each review and refute) and set `design: reviewed`.

### F6 [low] `deadWithin` reads a reused pid as alive: a false red the Design does not name
Where: Design ("Why this holds"); proto dispatch-cli.spec.luau `deadWithin`.
Evidence:
- If the dead grandchild's pid is reused, `kill -0` either succeeds (a process of the same user) or fails with "Operation not permitted" (another user's). Both read as alive under the rule that only "No such process" counts as death, so `deadWithin` returns false after 60 s for a grandchild that died.
- macOS hands out pids in sequence up to 99999. Probe: `./zn run --time 40 -- perl …` printed `pid0=42360 pid10=42389`, 2.9 a second at load 4.5.
- A false red therefore needs two things:
  - the pid numbers to wrap all the way round between the group kill and the first poll, a gap of seconds under load (the dispatcher's wrap-up and push, the case's `state()`);
  - the process that gets the reused pid to live for the rest of the 60 s.

  That is rare, and it can never cause a false green.
- zz-arch/children-need-a-lifeline asks this question of every stored pid ("what does a stored pid … name after the process is gone and the number is reused?").

Recommendation:
- Name it in the Design as the one false-red path left, with its odds.
- Optionally, write the grandchild's start time beside its pid (`ps -o lstart= -p $$`) and count a pid whose start time differs as dead. That adds a row and changes the golden and the pins.

Lesson: zz-arch/children-need-a-lifeline

Checked without a finding:
- AC3, recomputed:
  - `git diff 1808a041 proto-c0279 -- z-nile/tests/acceptance/c0117/dispatch-cli.spec.luau | grep -v '^index '` equals acceptance/dispatch-cli.spec.expected.diff byte for byte.
  - `git rev-parse proto-c0279:<spec>` and `git hash-object` in the proto worktree both give `de94e4b6…`.
  - origin/main (fetched, 47e6d0d8) still has blob `4fec0246…`, and the proto's merge base with it is 1808a041.
  - No commit on origin/main since 1808a041 touches fakecli, the spec, runner.luau or dispatcher.luau. AC3 runs from the z-nile home, and git prints the same repo-root paths there.
- pins.sh:
  - On 3e3648ad it exits 0. On main it exits 1 with 18 MISSING, PRESENT or DIFFERS lines.
  - The `mode()` anchors (`stop) `, `cap) `, `push) `) each match exactly one line of the proto's fakecli (61, 84 and 94).
  - fakecli-modes.expected equals the three entries.
- The final constants (root 120 s and 240 s, c0040 2 s and 30 s) agree across the proto spec, Design, Solution, AC1 and pins.sh. c0040's closer file overrides both keys (M7). No case outside c0040 ends by a stall: each mode the spec uses ends by its own signal or exits.
- Which commit each run used:
  - M1 to M4 and M7 fail at 13aca7c8's line numbers (701, 702, 660, 669, 715), as E7 says.
  - The final runs came from `loop3.sh` in proto-c0279. Their log files were rewritten from about 20:43, after 3e3648ad (20:43:25), and finished between 20:46:53 and 20:58:18, so they ran without the run-time bound, as E7 says.
  - The M8 fixture holds 120 s, 240 s and the hour-long hold (b9f6096a's files).
- `deadWithin` bounds its poll on the wall clock (`os.time`). The grandchildren `exec sleep 3600`, far past the bound plus everything before it. An escaped grandchild is stopped by the runner's sweeper (mutant-M3's log).
- FAKE_DELAY reaches the fake: the dispatcher adds the step's env to the inherited environment, the same way FAKE_DIR (set only by `zn`) reaches it, and M2 fails both delayed cases.
- stylua, selene and `luau-lsp analyze` are clean on the final two files. promote-check is OK, and `./zn lessons --uncovered c0279` and `--check` pass.
- control-cli, dispatch-guards and repo-fence use none of the stop, cap or push modes (control-cli calls `./zn dispatch stop` directly). The Overrides line names the one promoted spec the change edits.
- Repository safety:
  - AC1 and AC3 only read (`hash-object` without `-w`).
  - AC2's writes and the pid files stay in the spec's `.cache` fixture.
  - Every experiment script ran through `./zn run --time`.
- The two lesson notes added in round 2 (hold-on-markers-not-sleeps, spec-design-correspondence) are general.
- Executability: proto-c0279 exists only as a local branch (it is not on origin), but the golden diff and fakecli-modes.expected carry the exact text, so Step 1's "or write them from the Design" stands without the branch.

Lesson candidates (for the lead):
- z-design, a note on read-back-every-prototype-edit:
  - What happened: a mutation script that replaces the first occurrence of a pattern edits the wrong branch when the pattern occurs twice. In c0279, `if fs.isFile(stopFile) then` hit runner.luau:141 instead of :237, and the mutant that survived was then recorded as a hidden engine path.
  - Check: does each mutation edit refuse a pattern that occurs more than once, and was a surviving mutant read back in the copy the spec ran before its survival was explained?

Verdict: approve
