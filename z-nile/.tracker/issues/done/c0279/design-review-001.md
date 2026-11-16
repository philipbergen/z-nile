# Review 001: c0279 (design mode)
Inputs: prep `prep-dispatch-stop-spec` at 26f6efc7 (c0279.md, check.sh, acceptance/no-wall-clock.spec.luau); prototype `proto-c0279` at 06e4b72a (z-nile/tests/lib/fakecli.luau, z-nile/tests/acceptance/c0117/dispatch-cli.spec.luau); z-nile/engine/runner.luau, adapters.luau, models.luau, dispatcher.luau (stopAt); `./zn capture c0279`; the run logs r/base-1..5, r/after-1..5, base-dcli.out, base1.txt, base-1.txt, after-1.txt, mut-M1..M3 and mut.sh/mut2.sh in the session scratchpad; `./zn lessons --skill zz-review --full`, `./zn lessons --when design`.

### F1 [high] The first-line change does not cover the silence it blames: the preamble after it is still silent under the 2 s stall limit, the stop and push heartbeats start only after it, and no check exercises it
Where: Solution item 3; E2, E3; Design "Why the poll is not a wall-clock wait"; fakecli.luau:40-50 (proto); runner.luau:152 (`quiet = 0`), 200 (`quiet += dt`), 249 (`quiet >= limit` → stalled).
Evidence:
- The stall clock starts when `runner.run` starts and resets on every stdout chunk. After the new first `echo`, every mode still runs two `$(printf | sed | head)` substitutions, up to two `$(cat)` and the log block with `$(pwd -P)` before it prints again. `stop)`, `push)` and `scriptquota)` start their heartbeats inside `case`, after all of it. So the window the design blames ("a pipeline of sed/head/printf processes: a loaded machine took over 2 s to reach it") is still a silent window under the same 2 s limit. It now comes after one line instead of before it.
- Measured with the fixed fake's preamble verbatim: `./zn run --time 120 -- perl <scratchpad>/rv279/probe.pl <scratchpad>/rv279 40`, outside the jail, at load average 96.7 on 18 cores. Start to first line: median 0.010 s, max 0.021 s. First line to next output (the preamble): median 0.029 s, max 0.049 s. Perl start-up: 0.026 s. The preamble is about three quarters of the old silent window, and the whole window is about 40× under 2 s at this load. Moving the `echo` removes at most a quarter of the window. Whatever kept the fallthrough case's claude step silent for 2 s ("stalled (no output for 2 s), 0 tokens" in base-1.txt and after-1.txt) was not a slow preamble alone. A freeze of the machine, or of the dispatcher's own loop, would stall the fixed fake just the same: a starved `task.wait` adds its whole `dt` to `quiet` before the reader task can reset it.
- E3 does not test this. `FAKE_DELAY` only sleeps inside the stop and push heartbeats. The unfixed comparison put its 3 s sleep "first thing", before the first line, where it would stall the fixed fakes too. No run delays the fixed fakes' preamble, and AC1's third case only pins line order. So "the first line first is what makes startup slowness harmless to the fixed fakes" has no run behind it. E2 (5 of 5 green against 4 of 5 for the paired base runs r/base-1..5) cannot tell the difference.
Critique: the fallthrough case is one the load runs show failing, so the user's scope decision puts it in c0279, and this change is its only fix. The stop and push cases carry the same preamble before their heartbeats. The Design's "under any load the case can only get slower, never fail" holds for the `deadWithin` poll only: every case still runs under a 2 s wall-clock stall bound.
Consequences: a heartbeat over the preamble must stop before `case`, so the modes that test silence (stall, prose, wait, quietreview, cap, noids, calls) still go quiet. If the cause turns out to be the dispatcher's loop or the machine, no fake can fix it, and a stall limit in the spec's own fixture is the only lever short of a dispatcher change. That conflicts with the Non-goal's wording, which names `stall_seconds`.
Recommendation:
1. Measure first: an experiment through `./zn run`, inside the spec runner's jail. The fake writes a high-resolution time to its log at its first line, after the preamble, and at each beat. Run the fallthrough case under load until it stalls, then record where the 2 s went: before the first line, in the preamble, or between beats.
2. Then choose a fix that holds by construction for every case that does not test a stall:
   - (a) A stall limit that only a real stall reaches. The spec's root MODELS gets a `stall_seconds` that no correct run waits on (e.g. 60), with `tool_seconds` at least as large. The issue the stall cases use (c0040: wait, prose, stall, tool) gets a closer `.models.toml` with `[dispatch] stall_seconds = 2` and `tool_seconds = 8`. `models.settings` stacks `[dispatch]` per file, the same way c0020's closer file stacks `max_tokens`. Don't use c0010: the stray-file case writes and deletes `c0010/.models.toml`. Say in Non-goals that `stall_seconds` there means the dispatcher's default, not this fixture's file. The c0040 cases that must not stall (the tool case's 3 s quiet tool call under 8 s, the wait case's grok fallback) keep a 2 s window over their spawn; name that as the residual.
   - (b) And/or a preamble heartbeat: `( while :; do echo '{"type":"system"}'; sleep 0.5; done ) & boot=$!` as the first command and `kill $boot` just before `case`. A preamble without forks does the same: parameter expansion and `read` instead of `$(printf|sed|head)` and `$(cat)`. Only the spawn is left (about 0.05 s at load 97) plus a whole-machine freeze; name that residual.
3. Prove it with a check.sh run that delays the very window the fix claims to cover, with every case the fix covers passing. For (a), a 3 s sleep as the fake's first command; for (b), a 3 s sleep inside the preamble. Key the sleep off the stall cases' issue with a builtin `case "$*"` if they can't take it. Add mutant rows: the old 2 s root limit for (a), the preamble heartbeat removed for (b); each must fail on an assertion. Change AC1's third case to match, since it pins `'step=$(printf`, the pipeline (b) may remove.

### F2 [high] Two load-sensitive cases in dispatch-cli are outside a scope the user set as "every load-sensitive case in that file": the cap case by a Non-goal, the tool case by not being mentioned
Where: Problem, second Scope decision; Non-goals bullet 3; E1, E5.
Evidence: on proto, `grep -nE "absentAfter\(|deadWithin\(|task\.wait|stall_seconds|tool_seconds|minutes > 0|sleep [0-9]" tests/acceptance/c0117/dispatch-cli.spec.luau` hits lines 21-22 (`stall_seconds = 2`, `tool_seconds = 8`), 108/366/404/470/530 (reviewer `sleep 3`, inside a heartbeat), 340/694 (`minutes > 0`, safe under load), 662 (`absentAfter(grandchild-cap, 3)`) and 707 (`deadWithin(pid, 60)`). Paired with the fakes:
- fakecli.luau:62: the cap mode's `( sleep 2; touch "$FAKE_DIR/grandchild-cap" ) &` races the kill, against a 3 s wait. The design calls it "the same shape" and says such a grandchild "made a late kill look like no kill".
- fakecli.luau:79: the tool mode's 3 s quiet tool call runs against `tool_seconds = 8`, with the preamble (F1) under `stall_seconds = 2` before its `tool_use` line. Case at spec:686.

The user's quoted words are "Yes, every load-sensitive case in that file". The text after the colon ("that the load runs show failing under load") is the author's gloss, and it narrows "load-sensitive" to "seen failing". The Non-goal then drops the cap case because 18 runs showed 0 failures.
Critique: load sensitivity is a property of the case, not of a sample. The stop case passed 4 of the 8 base runs. Moving a case the user's words cover into Non-goals without a user line is a scope cut (z-design, Scope is what was captured).
Consequences: the cap fake prints its tokens at once, so the cap can kill the group before the grandchild has written its pid. The fake must wait (bounded) for the pid file before the heavy lines. That wait is silent under c0030's 2 s limit unless it beats. A beat is harmless here: the cap fires on tokens, and a cap that never fires still ends as `failed`, not `cap`. The Overrides line gains the cap case, and AC1 (or F4's whole-file pin) has to cover it.
Recommendation:
- Bring the cap case in with the stop case's pattern: the cap grandchild records its pid and outlives any wait (F7), the fake waits for the pid file before the heavy lines, and the case uses `deadWithin(<pid>, 60)`. Add the mutant row "the cap grandchild in its own group" (fails at `deadWithin`).
- For the tool case, either cover its preamble with F1's fix and record why its 5 s margin holds, or fix it.
- Put the search above and a verdict for each hit into E1, so the census can be rerun.
- If the author reads the decision as "only the cases seen failing", escalate to the user with the options: (i) every load-sensitive case (about 6 more lines for the cap case), or (ii) only the cases seen failing, with the cap case captured now as its own chore.

### F3 [high] With a heartbeat that runs until the group dies, a `dispatch stop` that kills nothing passes the stop case; the old fake caught it as `stalled`
Where: fakecli.luau:84 (stop mode); runner.luau:237 (the marker branch), 286 (`if outcome == "failed" and fs.isFile(stopFile)` → `stopped`); runner.luau:56 (the supervisor's `if ($done == $pid) { …; group(15); …}`); adapters.luau:422-423; dispatcher.luau:1916 (stopAt's `runner.killGroup`); Regression guard ("still pins that stop kills the step's whole group").
Evidence (reasoned from the code, not run: one run of this file takes minutes on this machine). The mutant "stop kills nothing" drops runner.luau:237's `early = "stopped"` branch and dispatcher.luau:1916. With the fixed fake:
1. The stop writes its marker and returns.
2. The heartbeat keeps the step alive through `sleep 20`, and then the fake exits 0.
3. The supervisor TERMs what is left of the group, the grandchild included.
4. `adapters.finish` returns `failed` ("exited without a token count"), and runner.luau:286 turns it into `stopped`.

The case then sees `r.ok` false, outcome `stopped`, a dead grandchild and a good retry. It passes, only 20 s slower. With the old fake, which went silent after one line, the same mutant stalls at 2 s and fails at `toBe("stopped")`.
Critique: the case no longer proves what its title says. The supervisor's exit cleanup kills the grandchild whatever the stop does, and `stopped` is reachable without any kill. The Rules table has no row for this mutant.
Consequences: the fake must not be able to end by itself after the stop. It needs a hold after the stop that outlasts the stall limit of the case's issue, and if F1 (a) raises c0060's limit, the hold must outlast that. A correct stop can't read as stalled however slow the machine is: the runner checks the marker before the stall (runner.luau:237 before :249), and the marker is written before the stop returns.
Recommendation: save the heartbeat's pid (`hb=$!`) and `kill $hb` right after `./zn dispatch stop` returns, then hold silently for longer than the case's stall limit (today's `sleep 20` against 2 s). A stop that killed nothing then ends only by the stall and reads `stalled`. Add and run the row "dispatch stop kills nothing (the runner's marker branch and stopAt's killGroup removed)", which must fail with `expected "stopped", got "stalled"`. Pin the order: the heartbeat ends after the stop and before the hold.

### F4 [high] AC1 pins substrings of the promoted spec it overrides: a hollow `deadWithin`, or an assertion deleted from any other case, passes check.sh
Where: acceptance/no-wall-clock.spec.luau case 1; check.sh AC1/AC2; Regression guard; Implementation steps 1-2.
Evidence:
- Case 1 checks only that the stop case's text has `grandchild-stop.pid`, `deadWithin(` and two expectation lines, and no `absentAfter`. A `local function deadWithin(_pid: string, _s: number): boolean return true end` passes it, and passes AC2.
- So does the prototype's own helper whenever `kill -0` fails for any reason other than a gone process (a refused signal, an empty or malformed pid): every failure reads as death.
- Deleting an assertion from another case also passes AC1 and AC2: `t.expect(has(l, "realgh pr merge")).toBe(false)` from the push case, or `t.expect(s.history[#s.history].tokens > 5000)` from the cap case.

The Overrides line lets the executor edit this promoted spec, and nothing checks the rest of it.
Critique: the chore's outcome is "the stop case changes and nothing else does", and only a whole-file pin checks that. M4 is listed, but the hollow helper and the deleted assertion are the same kind of mutant and are not.
Consequences: a whole-file pin taken in prep ties the executor to prep's base, so the steps must check the base blob and stop for a re-prep when it has moved. A promoted digest would make every later edit of dispatch-cli an override of c0279 too, so the pin belongs in check.sh only.
Recommendation:
- In check.sh, pin dispatch-cli.spec.luau whole: its exact text (LF line endings, no whitespace collapsing, so a line joined onto a comment shows) equals the base blob plus the reviewed hunks (`deadWithin`, the stop case, and the cap case after F2). Record the base blob's sha in the Design and check it as Implementation step 0.
- Make `deadWithin` count a process as dead only on `kill -0`'s "No such process"; any other failure is an error.
- Either move `deadWithin` into `fakecli` and give it behaviour cases in the acceptance spec (a live `sleep` reads alive within a short bound, a killed one reads dead, an empty pid errors), or let the pin cover its body.
- Add rows for a hollow `deadWithin`, an assertion deleted from another case, and a line joined onto a comment; each must turn red.

Lesson: zz-test/narrowing-pins-the-whole-file

### F5 [medium] AC2's delay is a knob the fixed fakes choose to honour, placed before the slow work: it cannot fail before the fix, and a push heartbeat stopped before git still passes
Where: check.sh AC2; Test plan (AC2 note); E4b; fakecli.luau:94 (push).
Evidence: `push) ( beat ) & hb=$!; sleep ${FAKE_DELAY:-0}; kill $hb; echo note …; git …; gh …` keeps every AC1 push pin (`sleep 0.5; done`, `FAKE_DELAY`, `kill $hb`). It passes AC2 whenever git, the wrapper and gh finish within 2 s, which they do on an idle machine, yet the heartbeat no longer covers the work the design says it must. The Test plan says AC2 "passes before only because the old fakes ignore FAKE_DELAY", while E4b says AC2 fails on the unfixed worktree. E1 shows that failure came from load (the push case `stalled`), not from the check's construction.
Critique: AC2's job is to keep the fixed fakes honest on a slow machine. That needs the delay inside the slow work, where the fake can't skip it.
Consequences: the harness's own `bin/git` (fakecli.new) is on the dispatcher's PATH too, so a delay there must be scoped to the step: only when `ZN_DISPATCH_DIR` is set and the subcommand is `commit` or `push`. The design must also check that the agent's wrapper actually reaches that git, or put the delay in the fake gh's `pr merge` instead. After F3, the stop's heartbeat window ends when the stop returns, so the stop's delay belongs before that.
Recommendation: inject AC2's delay into the commands the slow work runs (the step's git commit and push through the harness's git, the fake gh) instead of a sleep the fake opts into. Record that AC2 then fails on the unfixed fakes by construction. Add and run the row "push heartbeat killed before git runs". Correct E4b.

### F6 [medium] AC1's text pins are promoted at `done` and freeze today's text of a test library, including the slow pipeline itself
Where: acceptance/no-wall-clock.spec.luau cases 1-4.
Evidence: after `./zn done` this spec runs in every gate from z-nile/tests/acceptance/c0279.
- Case 3 requires `'step=$(printf` to exist after the `echo` line, which is the pipeline F1 (b) may remove.
- Cases 2 and 4 require the exact Lua-source spellings `echo '{"type":"system"}'; sleep 0.5; done`, `kill $hb` and `FAKE_DELAY` in fakecli's `stop)` and `push)` entries.
- Case 1 requires exact expectation lines, which any reformat breaks.

Any later chore that renames a mode, changes the beat or reformats fakecli turns the gate red and has to override c0279.
Critique: these are claims about today's text, and those belong in check.sh. Where a behaviour run can observe the rule (F1's and F5's injected delays), the pins only add ways to fail a correct change.
Consequences: an env-gated case runs only when check.sh sets the variable; once promoted it skips, so the behaviour checks have to carry the rule from then on.
Recommendation: gate the text pins on an env variable that only AC1's check.sh line sets (as f0158 did). Replace the fakecli pins with the behaviour checks F1 and F5 add, and drop the requirement that `'step=$(printf` exists.
Lesson: zz-test/promoted-specs-pin-rules-not-sets, zz-test/source-pins-name-what-the-design-names

### F7 [low] The grandchild's `sleep 120` holds by margin, not by construction
Where: fakecli.luau:84; Design ("cannot end by itself inside that bound").
Evidence: an escaped grandchild (M3) is caught only if its 120 s outlast everything from its start to the end of `deadWithin`'s 60 s. That means the pid wait, `FAKE_DELAY`, the stop and the dispatcher's wrap-up must take under 60 s. The design's own premise is a machine whose slowness has no bound.
Recommendation: hold the grandchild on a marker the case removes after its check (a bounded number of polls). Or let it sleep past any run's limit and have the case kill the pid when `deadWithin` fails, so no run leaks it. Do the same for the cap grandchild (F2).
Lesson: zz-test/hold-on-markers-not-sleeps

### F8 [low] The Lessons pass is deferred to after the review, yet the frontmatter says `design: reviewed`
Where: Unknowns & experiments, last bullet; frontmatter.
Evidence: "Lessons pass (`./zn lessons --when design --full`): recorded after the review, below." z-design step 5.1 runs it before the first round, names the lessons that changed the design, and only then marks `design: reviewed`. Three lessons would have changed this draft (F4, F6, F7).
Recommendation: run the pass now and record which lessons changed the design.

### F9 [low] E1's record doesn't match the logs, and several cited runs have no log
Where: E1, E3, E4, E4b, E6.
Evidence:
- The stop case failed in 4 of the base logs (base-dcli.out, base1.txt, base-1.txt, r/base-4.txt), not twice.
- base-1.txt has two failing cases in one run, against "each by one case". It also has no summary line (base-summary.txt: "bounded: the process that started it is gone").
- base-dcli.out is proto-c0265-base's run, not this prep's.
- No log exists for E3's 25/25 and 6/19, E4b, E6's "41 passed", M4 or M5. mut.sh scripted M4, but no mut-M4 file exists, and mut2.sh dropped it.
Recommendation: correct the counts, and keep a log for every run you cite (or quote its summary line) so the `run` rows can be checked.

### F10 [low] The same-shape wait in control-cli is left for "if a load run ever fails it"
Where: Non-goals bullet 3; E5.
Evidence: control-cli's `absentAfter(grandchild-orphan, 5)` waits on the orphan fake's `( sleep 3; touch … )`. The user's standing rule that promoted specs wait for nothing already makes it a defect, and a follow-up kept conditional gets lost. It is in another file, so it is outside c0279's scope.
Recommendation: the lead captures the chore now (z-ticket), naming the orphan case. If F2 is resolved by escalation, the same capture can take the cap case.

Checked without a finding:
- The first line `{"type":"system"}` is inert in all three adapters: claude reads `system` only for an error or message, grok has no branch for it, and agent lists `system` in `AGENT_TYPES` and starts no turn on it. So control-cli's `noids` and `calls` counts and the stall modes keep their meaning.
- Only `proto-c0279` changes the two files: a merge-base diff of every local and origin branch.
- No promoted spec pins either file by text or digest (`grep -rlF` over tests/acceptance with the paths and basenames), and `lune run z-nile/affected` prints `ALL`.
- AC1 only reads, and AC2's writes stay in `.cache` fixtures.
- The mutants ran through `./zn run --time 900` with `FAKE_DELAY=3`, and M1's `stalled` shows the knob reaches the fake.
- M1-M3 failed on the assertions E4 names (spec:703, :720, :707).

Lesson candidates (for the lead):
- zz-test: when a fake gains a heartbeat, ask how the step ends if the code under test never acts. A fake that beats until its group dies runs out its own hold and exits, and exit-time cleanup (the supervisor's group kill, a failed-plus-marker → stopped mapping) then produces the outcome the case expects. Check: with the action under test removed, how does the step end, and is that outcome different from the one the case asserts?
- z-design: a fix for a timing failure under load measures where the time went before choosing the fix. Check: does the design record a timing of each phase of the failing window under load, and does the fix cover the phase that measurement blames?

Verdict: changes
