# Review 003: R0003 (design mode)
Inputs: main plus uncommitted prep (R0003-sim-harness.md, R0003/check.sh, design-review-001/002.md, design-refute-001/002.md, c0010 doc, check.sh, acceptance/*.spec.luau, experiments/E1, c0034). I probed with a throwaway `tests/lib/sim.luau` written from the doc, in a scratch copy outside the repo. It passes all six acceptance specs (42/42) and AC1–AC6 of c0010's check.sh. AC7 fails only because the skill text doesn't exist yet. I also ran check.sh through the symlinked `/tmp/...` path, and it passed. I ran mutants of the prototype, each selected with an env var, against the six specs and against a probe spec.

Round 2: I checked every refutation, and each one is correct, so F1–F5 are dropped.
- F1: expect.spec:95 fails the recursive-partial mutant.
- F2: expect.spec:194 and :217 assert the replay path, `steps`, `failure.tick` and the state counts.
- F3: check.sh uses `pwd -P`, and c0034 carries the same fix.
- F4: AC7 greps for `timing exception`, and the Regression guard now describes what RC2 actually runs.
- F5: AC7 greps for `tests/integration/ is for`.

### F1 [high] Checking `stopWhen` before the expectations at the stop tick passes every spec and silently skips those expectations
Where: c0010 Design, Tick semantics line 37 ("true ends the run after the expectations at `t` were checked"); acceptance/expect.spec.luau "stopWhen ends the run early…" and "…never reached"
Evidence: No spec has an expectation at the tick where `stopWhen` fires. I made a mutant (`stopfirst`) that evaluates `stopWhen` right after the step, then breaks before `checkAt(t)`. It passes 42/42. It also skips the expectations at the stop tick completely, because the never-reached check is `at > steps` and here `at == steps`.
- Probe: Walker with `stopWhen = obs.x == 10` (fires at t = 5) and `sim.expect(5, { x = 99 }, "at stop")`. The correct harness fails. The mutant **passes**.
- This is the natural shape of a scenario ("stop when caught; at that tick lives = 2"), and the loop order that produces it is an easy one to write. The result is a silent pass, which is the class of bug the harness exists to prevent.
- The `stopWhen` arguments are also unchecked. Both cases ignore `events` and `t`. A mutant that passes `{}` for events and `k` for `t` (`stopevents`) passes 42/42. It breaks any "stop on the Caught event" scenario, which would then run to `ticks`.

Fix: Add these cases to expect.spec (still in prep):
1. On the existing Walker, `stopWhen = obs.x == 10` with `sim.expect(5, { x = 99 }, "at stop")`. The run must fail with `tick 5` and `at stop`, and the message must not contain `never reached`.
2. A `stopWhen` that records the `t` values it's called with and returns `#events > 0`, using a model that emits an event at a known step, for example script.spec's bumping Walker (Bump visible at t = 6). Assert `trace.steps == 6`, `trace.stopped`, and that the recorded `t` values are `1..6`.

### F2 [medium] `record = false` doesn't say that expectations still apply, and a harness that skips them passes
Where: c0010 Design, RunOptions line 55 ("false keeps only `final` (for speed)"); line 104; acceptance/script.spec.luau "record = false keeps only the final state"
Evidence: The only `record = false` case has no expectations. A mutant (`norecexp`) that skips `checkAt` when not recording passes 42/42. Probe: `sim.run(Walker, { seed = 1, ticks = 3, record = false, script = { sim.expect(2, { x = 99 }) } })` fails with the correct harness and passes with the mutant. The doc says only that `record = false` "keeps only `final`". Line 104 implies failures can happen with `record = false`, but nothing says expectations and `stopWhen` still run. So "only keep final, skip the work" is a defensible reading. The Scalability section steers long multi-seed runs, the ones f0023 needs, to `record = false`, which is exactly where every expectation would then be silently dropped.
Fix: In RunOptions and Tick semantics, say that `record` affects only what the trace and replay retain: expectations, `stopWhen`, never-reached and failure reporting behave the same either way. Add a script.spec or expect.spec case in which `record = false` with a failing expectation fails at its tick, and whose replay (if written) has empty `states`.

### F3 [medium] `sim.replay` can return the file's contents without re-running the model and still pass AC3
Where: c0010 Design, Replay file line 105 ("runs `seed` for `steps` ticks …"); acceptance/replay.spec.luau "sim.replay reproduces the recorded states and events"
Evidence: Every replay assertion compares the trace with the file (`states`, `events`, `steps`, `seed`, `final.log`), and those are all in the file. A mutant (`fakereplay`) that decodes the file, checks the model name and returns `{ states = doc.states, events = doc.events, final = doc.states[#doc.states], … }` without calling `model.new` or `model.step` passes 42/42. Such a replay is useless for the workflow the Docs prescribe: it doesn't hit breakpoints or prints in the model, and after a fix it still shows the old, failing states.
Fix: Add a replay.spec case that replays a failure with a same-named clone of `Drunk` that counts `step` calls, or whose `observe` adds a field. Assert that the count equals `doc.steps`, or that the trace's states differ from the file's.

### F4 [medium] Replaying a step error never reproduces the error
Where: c0010 Design, Replay file lines 103 and 105 (`steps` = k for a step error in step k; replay "runs `seed` for `steps` ticks with the intents at `at < steps`")
Evidence: For `crashy-seed1-tick4.json`, which expect.spec pins at `steps = 4`, `sim.replay` runs steps 0–3 and returns normally. Step 4, the step that raised, never runs, and an intent scripted at tick 4 is filtered out by `at < steps`. The same happens for "event without a string kind". The author gets a clean trace for the one failure type where replaying into the failing call is the point, so they can put a print in the failing step. Nothing in the doc or the skill's "how to re-run a replay" text warns about this, so an executor or a later author will read it as a bug.
Fix: Record the failure kind in the replay (`failure.kind = "expect" | "step" | "never"`). For `"step"`, specify that `sim.replay` also runs step `steps` with its intents, and lets its error propagate as a plain error without writing a new replay. Add a replay.spec case that asserts the replay raises `wall fell over`. Alternatively, keep the behavior but state it in the Design and the skill ("a step-error replay stops just before the failing step").

### F5 [low] Two documented copy and compare rules are unchecked
Where: c0010 Design, line 83 ("A function `want` is called with a deep copy"), line 110 (assertDeterministic compares "for t = 0, 1, …")
Evidence:
- A mutant (`fnref`) passes the recorded observation itself to function expectations, and passes 42/42. An expectation that normalises or sorts its argument then corrupts `trace.states` and the replay file.
- A mutant (`detmin`) compares only up to the shorter of the two runs, and passes 42/42. It misses a second run that ran longer, which happens when `stopWhen` closes over a leaked counter.
Both are narrow, and neither is likely to matter soon.
Fix: Optionally add one case each. A function expectation mutates `obs.pos`, and `sim.state(trace, t).pos` is unchanged. An impure `stopWhen` that fires only in the first run fails `assertDeterministic`.

Verdict: changes
