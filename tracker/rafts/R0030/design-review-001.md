# Review 001: R0030 (design mode)
Inputs: main a01ec69 plus uncommitted prep (R0030-sim-harness.md, R0030/check.sh, c0090 doc, check.sh, acceptance/*.spec.luau, experiments/E1). Probed with a throwaway `tests/lib/sim.luau` prototype in a scratch copy of the repo (all 36 acceptance cases pass; RC1/RC2 pass; promote-check reports no type errors in the acceptance specs).

### F1 [high] The partial-table expectation can use shallow `==` and still pass every acceptance spec
Where: c0090 Design, "Expectations" ("each key in `want` must deep-equal the observation's value"; "JSON for tables"); acceptance/expect.spec.luau
Evidence: Every table `want` in the specs has only number-valued fields (`{x = 8}`, `{x = 9, dir = 1}`, `{x = 7}`, `{x = 6}`, `{x = 0}`, `{x = 10}`, `{n = 3}`, `{n = 4}`). I switched my prototype's field comparison from deep-equal to `obs[k] == want[k]` and the six specs still passed, 36/36. That implementation would then fail every real scenario that expects a table-valued field. f0110/f0120 observations will have exactly such fields: a tile `{x, y}` or a heading vector. The "JSON for tables" message format is also unchecked.
Fix: Add a case in expect.spec where a table field passes when it deep-equals, for example `sim.expect(1, { seen = { "0:R" } })` on a walker that exposes a list. Add a second case where a table field fails, and assert that the message contains the JSON of both values.

### F2 [medium] `sim.replay` cannot replay a failure at time 0 (steps = 0) because its own validation rejects it
Where: c0090 Design, "Replay file" ("runs `seed` for `steps` ticks") against "Harness misuse" (ticks < 1 is rejected)
Evidence: expect.spec's "time 0 expectations check the initial state" produces a replay with `steps = 0`. A step error in step 0, or an event without a `kind` at step 0, does the same. In my prototype, which follows the doc literally, `sim.replay(M, ".cache/sim/m-seed1-tick0.json")` raised `sim: ticks must be a positive integer`. No spec covers replaying a steps = 0 file, so check.sh passes while the documented "re-run a replay" workflow is broken for the earliest failures.
Fix: Specify that a replay with `steps = 0` returns a trace containing only `new(seed)`'s observation, or let replay bypass the `ticks ≥ 1` rule. Add a replay.spec case that fails at time 0 and replays it.

### F3 [medium] A non-JSON-safe observation or intent hides the real failure behind a serde error
Where: c0090 Design, "Failures" and "Replay file" ("Intents and observations must therefore be JSON-safe")
Evidence: `@lune/serde` refuses integer-keyed or sparse tables. `serde.encode("json", { pellets = { [3] = true, [7] = true } })` raises `invalid type: integer 3, expected a string key`. A pellet set keyed by tile index is a natural observation for f0290 and f0120. With such a model, a run passes silently until its first failed expectation. Then the replay write throws inside the failure path, and the author sees a serde error instead of `sim[...] seed … tick …: label: field …`. NaN is also encoded silently as `null`, so "replay reproduces the file exactly" becomes false with no warning. The doc states the rule but gives no behaviour for when it's broken, and no spec covers it.
Fix: Build the failure message first. Write the replay under `pcall`. If the write fails, still raise the original message, with `replay: not written (<reason>)` in place of the path. Optionally encode the time-0 observation once per run so a non-JSON-safe model fails immediately with a clear error. Add one spec case for this.

### F4 [medium] The AC6 budget measures wall-clock time, not CPU time as the doc says, and becomes a permanent timing spec
Where: c0090 Design, "`sim.bench`" ("`os.clock()` CPU seconds"); E1; acceptance/bench.spec.luau:47; testing skill, "Good specs" ("no wall-clock time")
Evidence: In Luau, `os.clock` is a monotonic high-resolution elapsed timer. With Lune 0.10.5 here, `os.clock()` measured 0.302 across `task.wait(0.3)` with the process idle. So the budget includes time the process spends descheduled on a loaded CI runner. E1 tested monotonicity and resolution but not CPU versus wall time. After `done`, the spec is promoted into `tests/acceptance/c0090/` and runs on every full gate forever. It's the only spec in the repo whose result depends on elapsed time, against the testing skill's rule. The 150× margin makes a flake unlikely, but the doc's claim is false, and the rule exception isn't recorded anywhere.
Fix: Say "elapsed seconds (`os.clock`, monotonic wall time)" in the Design and in the testing skill. Record in the testing skill that bench budgets are the one sanctioned timing exception, with a generous margin required. Alternatively keep the interleaving cases in AC6 and run the budget as a non-gating `lune run` report.

### F5 [medium] c0090's check.sh, and therefore R0030's RC0, stops working after `tracker.sh done`
Where: tracker/issues/c0090/check.sh:4-5; R0030/check.sh RC0 member loop; RC2 comment ("after `done` … tests/acceptance/c0090/")
Evidence: `done` moves `acceptance/` out with `git mv`. Line 5 then runs `git -C "$A/.."` on a directory that no longer exists. On the already-done c0020, `bash tracker/issues/done/c0020/check.sh` prints `fatal: cannot change to '…/acceptance/..'` and `/scripts/lib/ac.sh: No such file or directory`, then `check: command not found`, and exits 127. c0090 copies the pattern. RC2 was deliberately written to work after promotion, but RC0 runs `bash "$dir/check.sh"` for c0090 and so fails after `done`. The raft's exit criteria can't be re-verified on the merged branch, for example by `tracker.sh check R0030` during PR review. This is a repo-wide pattern, but this raft explicitly claims to work after promotion.
Fix: While still in prep, resolve the root from the script's own directory: `ROOT=$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)`. Set `A` to the local `acceptance/` if it exists, otherwise `$ROOT/tests/acceptance/c0090`. Or file a chore for the template and all done items, and drop the post-promotion claim from RC2's comment.

### F6 [medium] AC7 doesn't check that the tick-semantics contract, which later rafts depend on, is documented
Where: c0090 check.sh:13-14; R0030 Whole-raft design ("The contract for later rafts is the tick semantics … The testing skill documents it")
Evidence: AC7 passes if SKILL.md contains the strings `tests/scenario/`, `@tests/lib/sim` and `replay` anywhere. A single table row plus the word "replay" satisfies it. The "Simulations" section with the five tick-semantics bullets can be left out and check.sh still passes. f0110 and f0120 are told to match semantics that would exist only in `tests/lib/sim.luau`'s code.
Fix: Add a grep for a distinctive phrase of the contract that the doc prescribes verbatim, for example require that the skill contain `visible at` and `step k`. Put that exact wording in c0090's Docs section.

### F7 [low] Replay contents are underspecified for `record = false` and "never reached" failures
Where: c0090 Design, "Replay file" ("`steps` … for an expectation failure at time `t` that's `t`"; "states: observations at times 0..steps")
Evidence: "Never reached" is called an expectation failure at time `at` (for example, 20), yet `steps` can only be the stop tick (5), so the two statements conflict. With `record = false`, the harness has no states or events to write, but the file is specified to hold states 0..steps, and `sim.replay` reproduces the file's states. Two executors would write different files, and nothing checks either.
Fix: State `steps` = steps completed in every case, including never-reached. State that with `record = false` the replay holds `states`/`events` as recorded (empty). Or make failures always record by forcing `record = true` internally until the first failure.

### F8 [low] Intents are delivered by reference, so a model that mutates an intent breaks `assertDeterministic` and the replay script
Where: c0090 Design, "Tick semantics" (intent delivery) and "`sim.assertDeterministic`"
Evidence: Both runs of `assertDeterministic` deliver the same script item tables. If a step writes to an intent table (for example, marks a turn as consumed), the second run sees the modified intent and falsely reports `nondeterministic`. The replay file then records the modified intent. The doc says observations are deep-copied but says nothing about intents.
Fix: Specify that each delivered intent is a deep copy, or frozen, and that the replay file records the script as written.

Verdict: changes
