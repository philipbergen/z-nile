# Review 002: R0030 (design mode)
Inputs: main a01ec69 plus uncommitted prep (R0030-sim-harness.md, R0030/check.sh, design-review-001.md, design-refute-001.md, c0090 doc, check.sh, acceptance/*.spec.luau, experiments/E1, c0330). Probed with a throwaway `tests/lib/sim.luau` written from the doc alone, in a standalone scratch git copy of the repo. It passes all six acceptance specs (41/41), and with a minimal walker fixture, scenario spec and skill text the raft check.sh passes 5/5 before and after a simulated `done` (acceptance `git mv`'d to tests/acceptance/c0090, issue and raft moved to done/). promote-check type-checks the specs with 0 errors. Environment-driven mutants of the prototype were run against the specs.

Round 1: I checked each refutation against the specs and a mutant. All eight are right, so F1–F8 are dropped. The shallow-`==` mutant now fails 1 case. The by-reference intent mutant fails. A steps = 0 replay works. The integer-keyed observation reports the real failure. check.sh works after promotion (5/5 RC with the raft in done/). AC7 greps the three sentences.

### F1 [high] A recursive partial matcher passes every acceptance spec, so `{ seen = {} }` or `{ pos = { x = 6 } }` pass against observations they don't match
Where: c0090 Design, "Expectations" ("partial match on the observation's top-level keys: each key in `want` must deep-equal"); acceptance/expect.spec.luau
Evidence: Every table-valued `want` in the specs is complete: it names every key of the observed sub-table (`pos = { x = 6, y = 0 }`, `{ x = 7, y = 0 }`). A natural wrong reading applies the partial match recursively: for each key in `want`, match `obs[k]` against `want[k]` the same way. I used that as the field comparison (`SIM_MUT=recpartial`) and the specs passed 41/41. Under that mutant, on a model observing `{ pos = { x = 6, y = 3 }, seen = { 0 } }`, both `sim.expect(1, { pos = { x = 6 } })` and `sim.expect(1, { seen = {} })` **pass**. The correct implementation fails both, with `field "pos": expected {"x":6}, got {"x":6,"y":3}` and `field "seen": expected {}, got [0]`. For the game, this means "no ghosts in the house" (`{ ghostsInHouse = {} }`) or "pellets list is empty" would pass for any value. That's the silent-pass class of bug the harness exists to prevent, and the design's "partial only at the top level" rule is exactly what's untested.
Fix: Add one case to expect.spec (still in prep, so not sequestered yet): `sim.expect(1, { pos = { x = 6 } }, "sub")` on the existing Walker (observation `pos = { x = 6, y = 0 }`) must fail with `field "pos"`. Optionally add an empty-list case, e.g. a model observing a non-empty list against `want = { list = {} }`.

### F2 [medium] The replay write on step-error and never-reached failures is untested, and a harness that skips it passes AC3
Where: c0090 Design, "Failures" ("expectation, never-reached expectation, or an error raised by `step` raise one error … `replay: .cache/sim/…`"); acceptance/expect.spec.luau "an error inside step…" and "…never reached"; replay.spec.luau
Evidence: Every replay.spec case fails through a scripted expectation. The step-error and never-reached cases in expect.spec check only the message's model, tick and text. I made two mutants. One raises `sim[crashy] seed 1 tick 4: step raised: …` with no replay (`stepnoreplay`). The other raises the never-reached message with no replay (`nrnoreplay`). Each passes 41/41. A crash deep in a long scenario is the case where a replay helps most, and the `steps = k` and `failure.tick` rules for these paths (from round 1's F7) are never exercised. The "event without a string kind" path has the same gap.
Fix: In expect.spec's step-error case, assert the message contains `replay: .cache/sim/crashy-seed1-tick4.json`, and that the file decodes with `steps = 4` and `#states = 5`. In the never-reached case, assert a `replay: .cache/sim/…-tick20.json` path whose file has `steps = 5` and `failure.tick = 20`.

### F3 [low] c0090's check.sh fails before `done` when it is invoked through a symlinked path
Where: tracker/issues/c0090/check.sh:4,8 (`HERE="$(cd … && pwd)"`, `A="$HERE/acceptance"`); tests/run.luau prefix strip against `process.cwd`
Evidence: `HERE` is the logical path, but ac.sh `cd`s to the physical toplevel, and tests/run strips only a `process.cwd` (physical) prefix. I ran `bash /tmp/claude-501/…/repo/tracker/issues/c0090/check.sh` in the scratch copy (`/tmp` → `/private/tmp` on macOS). All seven checks failed with `error requiring module "..//tmp/…/script.spec": could not resolve child component "tmp"`. The same file passes when invoked via `/private/tmp/…` or by `tracker.sh check`, which uses a relative path. After promotion the fallback uses `$PWD` and is unaffected. The testing skill's template has the same trait, so this isn't new, but the round-1 F5 fix is new code with it.
Fix: `HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"`. Mention `pwd -P` in c0330 so the template gets it too.

### F4 [low] Two documented obligations are unchecked or misstated
Where: c0090 Docs ("the bench timing exception and its 50× margin rule"), check.sh AC7; c0090 Regression guard line 190
Evidence:
- AC7 doesn't grep for the timing exception. The skill's "Good specs" rule ("no wall-clock time") can stay unqualified while `tests/acceptance/c0090/bench.spec.luau` becomes a permanent timing spec. That was the substance of round-1 F4.
- Regression guard says "RC2 checks that the full gate leaves `git status --porcelain` unchanged". RC2 actually runs only the scenario specs and c0090's acceptance specs. The full gate runs in RC0, before RC2 takes its `before` snapshot, so a gate that dirties the tree isn't caught.
Fix:
- Add a verbatim phrase for the exception (e.g. `timing exception`) to the Docs section and to AC7's grep list.
- Reword the Regression guard to match what RC2 does.

### F5 [low] The new `tests/scenario/` tier overlaps `tests/integration/` without a rule for choosing between them
Where: c0090 "`tests/scenario/` (new tier)" and Docs table row; testing skill's `tests/integration/` row ("headless cross-feature scenarios, for example simulating a whole level")
Evidence: After this raft, "simulating a whole level" fits both rows. f0220's "idle player is caught within N–M s across 20 seeds" could go in either tier. Future executors will split scenarios arbitrarily, and prep reviewers will have no rule to check placement against.
Fix: Have the Docs section say how to choose. For example: anything driven through `@tests/lib/sim` goes in `tests/scenario/`, and `tests/integration/` is for non-tick cross-feature checks. Or retire the `tests/integration/` example in the same edit.

Verdict: changes
