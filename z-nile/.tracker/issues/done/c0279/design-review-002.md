# Review 002: c0279 (design mode)
Inputs: prep `prep-dispatch-stop-spec` at 23ae050b (c0279.md, check.sh, acceptance/pins.sh, acceptance/dispatch-cli.spec.expected.diff, experiments/*.txt, harvest.md, design-review-001.md, design-refute-001.md, the two new lessons); prototype `proto-c0279` at 13aca7c8 (`git diff 1808a041 proto-c0279`: fakecli.luau, dispatch-cli.spec.luau); z-nile/engine/runner.luau (run loop, killGroup, SUPERVISOR), adapters.luau (finish, the claude `rate_limit_event` branch), dispatcher.luau (stopAt), credential.luau; tests/lib/fakecli.luau (zn, clear), tests/lib/trackerfix.luau (new), tests/tooling/repo-fence.spec.luau (NAMES); `./zn capture c0279` (e88f68b6, a confirmed capture, no marker); `./zn lessons --skill zz-review --full`, `./zn lessons --when design --full`. Probes, all through `./zn run`: pins.sh and AC3's diff command in the proto worktree (exit 0, exit 0); pins.sh in the main checkout (exit 1, 15 MISSING/PRESENT lines); `stylua --check`, `selene`, `luau-lsp analyze --platform=standard` on the proto's two files (clean); `./zn promote-check c0279` (OK); `./zn lessons --uncovered c0279` and `--check` (ok); a deadWithin drift probe (F2). No spec run (machine load).
Dropped from design-review-001: F1 (the root limit answers it; what is left is this round's F1, a scope question), F5 (no heartbeat is left to hide behind; AC2 is stated as a guard and AC1/AC3 are what fail before), F6 (pins.sh runs from check.sh only), F10 (another file; the coordinator's).

### F1 [high] Two sub-cases that the user's "every load-sensitive case in that file" covers stay load-sensitive by the design's own account, fenced off by a Non-goal and the author's gloss (repeat of design-review-001 F2)
Where: Problem, second Scope decision line; Non-goals bullet 3; Regression guard; E5; the spec fixture's `c0040/.models.toml`.
Evidence:
- `./zn capture c0279` (e88f68b6) carries only "Capture it now". The second line was added in prep (26f6efc7). The user's words in it are "Yes, every load-sensitive case in that file". The text after the colon ("every case … that the load runs show failing under load") is the author's, and round 1 F2 already named it as a narrowing. It is unchanged.
- Non-goals: "The cases that test a stall (…) keep their 2 s stall limit, because the stall is what they prove; their residual load sensitivity is named in E5." E5: "the stall cases at 2 s keep a startup-time exposure".
- Which sub-cases are exposed:
  - In `wait)` (`echo 'Usage limit reached…'; sleep 20`) and `tool)` (`echo <tool_use>; sleep 3; …`), the 2 s stall limit applies from the spawn until the first line is read (runner.luau:236: the limit is `stallSeconds` while no tool call runs).
  - Two counted seconds of quiet in that window give `stalled`. The wait case's `zn(...).ok` (spec:669) and the tool case's `r.ok` (spec:688) are then false.
  - `prose` and `stall` expect `stalled`, so they are not exposed.
- The counted quiet belongs to the dispatcher, not only to the fake. runner.luau:200 `quiet += dt` adds the whole of a starved `task.wait(0.05)`. A reader reset at :162 that runs first does not help, because the main loop adds that `dt` afterwards. So a stall of 2 s or more in the dispatcher process during that window kills the step however fast the fake is.
  - This is the mechanism E1b blames ("the 2 s are the dispatcher's and the machine's").
  - unfixed-run-B.txt shows it: `zz-review on claude: stalled (no output for 2 s), 0 tokens`, with the fake's 0.5 s heartbeat running.
  - The window is shorter for these two sub-cases than for the fallthrough, but the failure is the same kind.
- "The stall is what they prove" does not force 2 s.
  - The tool case proves that a quiet tool call longer than the stall limit lives until the tool limit.
  - The wait case proves that a stall after the CLI's wait message counts as quota.
  - Any limit S works if the tool fake's quiet sits between S and `tool_seconds`. 2 s is a choice made for speed.

Critique: the user's words cover these sub-cases, and the design leaves them load-sensitive on purpose, with no user line. The tempting answer is "they never failed in 15 runs". But the stop case passed 5 of 8 base runs too: load sensitivity is a property of the case, not of a sample.

Consequences:
- A wider c0040 bound lengthens the wait, prose and stall sub-cases (each ends at S), and the tool case (its quiet must exceed S).
- That bound changes the `tool)` fake. No other spec uses it: control-cli's modes are calls, noids, questions, quota, waitplain, waitreview, ticket, quietreview, reviewer, silenttool, slowreview, claim, late, ok, orphan, script, tripwire and author, and `grep -n '"tool"\|"wait"'` over dispatch-guards, repo-fence and control-cli finds nothing.
- It also changes AC1's closer pin, the golden diff and M7.
- A dispatcher fix (charge a starved tick only up to a cap, e.g. `quiet += math.min(dt, 0.25)`) removes the exposure for every limit. But it changes `z-nile/engine/`, against the captured "nothing else in c0117's dispatcher changes" and Non-goal 1.

Recommendation: escalate to the user: one question, with these options and their costs:
- (i) Keep the full scope, with a bound sized from a measurement.
  - Time the spawn-to-first-line window inside the spec runner's jail under load, per the author's own new lesson z-design/measure-where-the-time-went.
  - Then give c0040 e.g. `stall_seconds = 10`, and the tool fake a 12 s quiet under `tool_seconds = 30`.
  - Add to AC2 a delay before the wait and tool modes' first line (FAKE_DELAY, or a knob of their own). The old 2 s limit fails it; the new bound passes it.
  - Add the row "c0040 back at 2 s, with that delay": the wait and tool cases fail.
  - Cost: about +33 s per run of a spec that already takes about 143 s unloaded (c0247 design-review-003).
- (ii) Accept the residual. The user's words become a `Scope decision` line that names the two sub-cases and their exposure.
- (iii) The dispatcher fix above. It needs a user line, because the capture excludes dispatcher changes.

Whatever the answer, replace the gloss after the colon with what the user decided.
Lesson: z-design/never-narrow-captured-scope, zz-review/no-scope-cut-as-fix

### F2 [medium] The grandchild's `exec sleep 120` does not outlast `deadWithin(..., 60)` under load, so a broken group kill can pass (repeat of design-review-001 F7)
Where: proto dispatch-cli.spec.luau:145-157 (`waited += task.wait(0.1)`); fakecli.luau:61 and :84 (`exec sleep 120`); the Design's "Why this holds under any load" ("a margin that cannot shrink with load … a sleep that ended by itself would need 120 s of the case's 60"); design-refute-001 F7.
Evidence:
- `waited` adds up only what `task.wait` returns. Each of the ~600 polls also runs `process.exec("kill", …)`, a fork and exec that is never counted.
  - Probe with deadWithin's loop polling a live pid, at load 10: `./zn run --time 120 -- lune run <scratchpad>/rv2/drift.luau <pid> 20` printed `bound=20.0 waited=20.00 wall=21.12 polls=200 mean_exec_ms=3.8`.
  - The drift is roughly polls times exec latency, and exec latency grows with load.
- Before the poll starts, the grandchild has already lived through the pid wait, FAKE_DELAY, `./zn dispatch stop`, the dispatcher's wrap-up (state, spend row) and the case's `state()`. All of that also grows with load.
- This repo's records show far higher loads than E2's 47-97: R0052 review-002 has a gate "ended at load 165" and "an earlier run at load ~600".
- At about 0.1 s per exec, 600 polls add 60 s, so `deadWithin` runs about 120 s of wall time after a case that is already stretched. Then the grandchild's own `sleep 120` ends inside the poll, `kill -0` says "No such process", and M3 or M4 passes.
- The refute's reason ("a sleep cannot run short under load, and the fake's pid wait is bounded at 60 s") is true, but it leaves out both stretches.

Critique: the old `absentAfter` caught a broken kill under any load, because the touch came at 2 s, and paid for it with false reds. The new check turns false reds into false greens at high load. The Design claims it holds both ways by construction.

Consequences:
- A longer hold leaves a surviving grandchild running after a broken-kill run until something stops it. M3's log shows the runner's sweeper doing that ("sweeper: stopped 1 process(es) the specs left running").
- The new hold text changes AC1's `exec sleep 120` pin and the golden diff.

Recommendation:
- Hold the grandchild far past any run, e.g. `exec sleep 3600`, bounded by the sweeper. Or hold it on a marker that the case removes after its `deadWithin` (zz-test/hold-on-markers-not-sleeps).
- Measure `deadWithin`'s bound in wall time (`@lune/datetime`), so that "60 s" means 60 s.
- Correct the Design sentence, and regenerate pins.sh's hold pin and the golden.
- Rerun M3 and M4 and keep their logs.
Lesson: zz-test/hold-on-markers-not-sleeps

### F3 [medium] Row 3's mutant (M1) fails whether or not the 120 s silent hold is there, so the rule it is listed for is untested; the mutant that needs the hold was not run (repeat of design-review-001 F3's row)
Where: Rules and mutants row 3; E4 (M1); Solution item 2 ("After the stop the stop fake goes silent and holds 120 s, so a stop that kills nothing ends in a stall"); design-refute-001 F3.
Evidence (reasoned from the code, since a spec run per mutant was out of reach here):
- M1 replaces `./zn dispatch stop` with `true`, so no marker is ever written (stopAt writes it, dispatcher.luau:1912).
- With the reviewed hold (`sleep 120`), M1 stalls at 60 s and reads `stalled`. experiments/mutant-M1 shows spec:701 `expected "stopped", got "stalled"`.
- With the old short hold (`sleep 20`), M1 still fails:
  - The fake exits 0 after printing only `{"type":"system"}`, so adapters.luau:422 returns `failed` ("exited without a token count").
  - runner.luau:286 maps `failed` to `stopped` only when the marker exists, and here it doesn't.
  - So the case fails with `expected "stopped", got "failed"`.
- So M1 dies with or without the hold.
- The mutant that needs the hold is round 1 F3's: the marker is written but nothing acts on it (runner.luau:237's early `stopped` branch and dispatcher.luau:1916's `runner.killGroup` removed).
  - With `sleep 120`, the 60 s stall gives `stalled` and the case fails.
  - With a hold under 60 s, the fake exits and the supervisor's exit cleanup TERMs the group, grandchild included. :286 then turns failed-plus-marker into `stopped`, so the case passes.
- AC1's `sleep 120 ;;` pin is what holds that line, and nothing shows that the pin is load-bearing.

Critique: the table marks a rule `run` when its mutant cannot tell the rule's presence from its absence. z-design/spec-design-correspondence asks: "Is each new case's recorded mutant killed by that case itself…?"
Consequences: none beyond two prototype runs.
Recommendation:
- On the prototype, with FAKE_DELAY=3, run the engine mutant: runner.luau:237's branch and dispatcher.luau:1916 removed. It must fail at spec:701 with `got "stalled"`.
- Run the pair too: that mutant plus the hold cut to `sleep 20`. It passes, which shows that the hold (and AC1's pin on it) is what kills the mutant.
- Record both logs, make the engine mutant row 3's mutant, and keep M1 as an extra row.
Lesson: z-design/spec-design-correspondence

### F4 [medium] AC1 pins fakecli only by unordered substrings, so a wrong fake passes AC1-AC3 (the round-1 F4 mechanism, which the revision fixed only for the spec)
Where: acceptance/pins.sh lines 25-38; Test plan AC1; check.sh AC1.
Evidence: each fake below passes AC1, passes AC2 against a correct dispatcher, and passes AC3 (which reads only the spec):
- (a) `sleep ${FAKE_DELAY:-0}` placed after `./zn dispatch stop`.
  - pins.sh asks only that the stop entry contain `FAKE_DELAY`.
  - The marker then lands before the delay, so AC2 never runs a slow stop, and M2 no longer fails the stop case except by chance.
- (b) A heartbeat spelled differently, `( while true; do echo '{"type":"system"}'; sleep 0.5; done ) &`.
  - The absence pin is the fixed string `while :; do echo`, so it misses this spelling.
  - Round 1's F3 comes back: with F3's engine mutant, the step lives through the 120 s hold, exits, and is mapped to `stopped`.
- (c) The pid written by the fake's own shell: `sh -c "echo $$ > …; exec sleep 120" &`, in double quotes.
  - The pins still see `grandchild-stop.pid` and `exec sleep 120`.
  - `deadWithin` then proves only that the leader died, and M3 (the grandchild in its own group) passes.

Critique: pins.sh claims "the fakes hold the shape the Design names". That shape includes order and which process the pid names, and substrings check neither. pins.sh runs only from check.sh, so exact pins cost nothing after `done`.
Consequences: exact pins freeze the three entries for the raft's duration. Step 0 already stops when main moves them, and another member editing them would conflict as text anyway.
Recommendation:
- In pins.sh, require each of the `stop)`, `cap)` and `push)` entries to equal its prototype text exactly (a fixed-string match of the whole joined entry).
- Drop the substring tests these replace.
- Add rows (a), (b) and (c), each of which turns AC1 red.
Lesson: zz-test/narrowing-pins-the-whole-file, zz-test/source-pins-name-what-the-design-names

### F5 [medium] AC3 takes its base from the local `origin/main`, a ref the executor can move, and no step covers a mid-raft merge that moves the spec
Where: check.sh AC3; Implementation step 0.
Evidence:
- `git merge-base HEAD origin/main` reads `refs/remotes/origin/main`, which the executor can move. The bypass:
  - commit X on a side branch, holding a weakened spec without the reviewed hunks;
  - HEAD = X plus the hunks;
  - `git update-ref refs/remotes/origin/main X`.
  - `git diff X` then equals the golden, and AC3 is green while the branch carries the weakening. That is M5 or M6, the mutants only AC3 kills.
- The repository's other checks of a branch's own change read the published tip instead:
  - c0114's `finished.luau` uses `git ls-remote origin refs/heads/main` ("never a local ref the author can move: decided with the user, 2026-10-23");
  - R0087/c0269's AC4 does the same.
- Step 0 checks the base only at the start. A merge of a main that has moved the spec turns AC3 red, and no step says what to do then.

Critique: the code reviewer's `./zn sync --fetch` resets the ref, so a forged ref would probably be caught in review. Still, AC3 is the only check that kills a hollow `deadWithin` or a deleted assertion, so its reference carries weight.
Consequences: a base read with ls-remote needs the network at check time, and is red when unreadable (as c0269's is). A pin on the result needs no base at all.
Recommendation:
- Step 0 already freezes the base blob, so pin the result: AC3 becomes `git hash-object tests/acceptance/c0117/dispatch-cli.spec.luau` equal to the reviewed blob (today `238f2a6e964546d93a8917fb312a726774f26158`; regenerate it after F2).
- Keep the golden diff as the readable record of that blob.
- Extend step 0 with: "and after any merge of origin/main that touches the spec or the three modes, stop for a re-prep".
Lesson: z-design/exact-checks-compare-against-the-merge-base, zz-review/sequestration-reference-not-a-ref

### F6 [low] Three harvest entries name lessons that do not teach their finding
Where: harvest.md.
Evidence:
- F5 → `zz-test/new-commands-run-in-a-copy`. That lesson is about running a new command in a fixture copy rather than the real tree. F5 was about a delay knob that the fixed fakes choose to honour.
- F7 → `one-off`. But round 1 put `Lesson: zz-test/hold-on-markers-not-sleeps` on it, and that lesson's text ("a 30 s sleep lets a broken lifeline pass whenever the case around it takes longer") is the finding.
- F9 → `z-design/spec-design-correspondence`, which is about matching Design rules to spec rows. F9 was about a record that did not match its logs.
Recommendation:
- F5 → `z-design/measure-where-the-time-went`, whose last sentence covers it.
- F7 → `zz-test/hold-on-markers-not-sleeps`. Sharpen its check with F2: is the hold compared with the poll in wall time, counting the poll's own commands and whatever runs before it?
- F9 → a lesson about records citing their logs (e.g. `zz-review/run-the-evidence-you-cite`), or a new one.

### F7 [low] The record overstates or misattributes in places, and two process steps are off
Where: E1, E1b, E5, E6; Design; frontmatter; spend.md.
Evidence:
- E1's push failure is one of the runs behind the user's second named case. It has no log and no quoted line, which round 1 F9 asked for.
- E1b states "the 2 s are the dispatcher's and the machine's" as a finding. The only measurement is round 1's preamble probe, taken outside the jail, and no run timed the failing window.
- E5 calls the residual "a fake slower than 2 s to its first line", but the mechanism is the dispatcher's starved tick (F1).
- E6's "41 passed" ran on an earlier draft and has no log.
- The Design says `deadWithin` polls `/bin/kill`, but the code runs `kill` from PATH.
- "The 60 s stall limit cannot be reached by a fake that is slow" claims a proof for what is a 60 s bound.
- `design: draft`: z-design step 5.1 marks `design: reviewed` once the lessons pass is done. The refute's answer to round 1 F8 reads the rule backwards.
- origin/main's spend.md has no design-review or design-refute rows for round 1 (z-design steps 5.2 and 5.3).
Recommendation:
- Quote the push failure's line.
- In E1b, say who measured what; reword E5 to describe the mechanism.
- Log E6's count or drop it.
- Say `kill` (from PATH) in the Design.
- Reword the 60 s sentence as a bound.
- Set `design: reviewed`.
- Record the round-1 spend rows.

Checked without a finding:
- No case outside c0040 relied on the 2 s stall to end a step. The modes the spec uses (`grep -n 'mode("'`) are script, scriptquota, quota, fail, nocount, cap, wait, prose, stall, tool, stop, push and ok.
  - `quota` and `scriptquota` end on claude's `rate_limit_event` "rejected" (adapters.luau:165-167), an early `quota` at runner.luau:247, never on the stall.
  - `cap` ends at the token cap, and `stop` ends at the marker.
  - Every other mode exits by itself.
  - `stalled` is asserted only at spec:678, on c0040.
- The 60 s root limit weakens no assertion. No case bounds a duration from above, and `minutes > 0` (spec:296, 338, 692) only gets easier under load.
- c0040's closer stacks `[dispatch]` per key: M7 fails when it is dropped. The tool case still proves its rule (a 3 s quiet tool call against a 2 s stall limit, under 30 s).
- Fail-before:
  - AC1 is red on main (exit 1, 15 lines) and green on the proto (exit 0).
  - AC3 is green on the proto (exit 0) and red on main by construction (an empty diff).
  - AC2 passes before, and the Design now says it is a guard.
- The proto's two files pass stylua, selene and luau-lsp. promote-check and the lessons checks are ok.
- The base blob `4fec0246…` is unchanged on origin/main. 1808a041 is on main and is the proto's merge base.
- `git grep` over origin/main's open issues and active rafts finds no other item that edits the spec or fakecli. c0247's review only quotes dispatch-cli's runtime, and R0087 touches neither file.
- control-cli, dispatch-guards and repo-fence do not use the stop, cap or push modes. repo-fence's NAMES list gains no hit from the new text.
- Repository safety: AC1 and AC3 only read. AC2's writes, the new `grandchild-*.pid` files included, stay in the spec's `.cache` fixture, and `fakecli.clear` removes them.
- The mutant logs fail on the assertions E4 names: M1 spec:701, M2 :701 and :715, M3 :702, M4 :660, M7 :669. E1's counts match the logs (A, B and load-4 red; load-1, 2, 3 and 5 green), plus the unlogged check run.
- The two new lessons are general enough that another raft could fail them.

Lesson candidates (for the lead):
- zz-test (a note on hold-on-markers-not-sleeps). A poll whose bound adds up `task.wait`'s returns does not count its own commands (`process.exec` per poll), so under load its wall time is several times its bound. A hold that has to outlast a poll is compared with the poll's wall time, plus everything that runs before the poll starts. Check: in wall time, at load 600, does the held process still outlive the start of the case plus the whole poll?
- z-design (a note on spec-design-correspondence). A mutant listed for a rule must die because of that rule. Weaken the rule's mechanism (shorten the hold, drop the pin) and check that the mutant then survives. Check: with the rule's mechanism removed, does this row's mutant still fail the case? If it does, the row tests something else.

Verdict: changes
