# Review 002: c0153 (design mode)
Inputs: prep-frame-roundtrip-tolerance 5de3e9c4 (c0153.md, check.sh, acceptance/golden.spec.luau, acceptance/plain.spec.luau, experiments/c0153.patch, experiments/mutants.py, harvest.md, design-review-001.md, design-refute-001.md); `./zn capture c0153` (d00df6eb); f0125 on origin/main; `git worktree list`. Evidence run in a scratch clone of the worktree checked out at today's origin/main 6390a4bc, with the item folder copied in and `c0153.patch` applied (scratchpad `dr2/repo`).
Dropped from design-review-001: none dropped; F1–F5 are fixed (verified below).

Round-1 fixes, re-run, not read:
- The five base blobs in Design "The base" equal both HEAD and today's origin/main 6390a4bc (`git rev-parse <ref>:pickman/tests/acceptance/<f>.spec.luau`, all five identical), so step 0 passes today.
- On 6390a4bc with the patch: c0153's specs plus the five narrowed specs `52 passed, 0 failed, 7 spec files`; `./zn check c0153` 3/3; `./zn promote-check c0153` OK. With the patch reversed: AC1 red on the missing `@tests/lib/plain`, AC2 red on all five digests, AC3 green (the old exact compares), the right reasons.
- `python3 -I experiments/mutants.py` (TMPDIR in my scratchpad): intended `52 passed`; G1–G10 and P1–P11 all `killed`. F1 (whole-file pins, comment join, spaces in strings), F3 (NaN, NaN eps), F4 (holes, sparse, odd keys, mixed, `"\xff"` not raising) and F5 (reason texts) hold.
- Every item `check.sh` still names its spec (`grep -nF "<file>.spec.luau" done/<id>/check.sh`: f0013:13, f0018:13, f0030:11, f0032:12, f0100:14). No in-flight branch or worktree edits any of the five files or `tests/lib` except R0056's `fakeengine.luau` (`git -C .worktree/<w> diff --stat origin/main...HEAD -- <the five> pickman/tests/lib` over R0055, R0056, raft-white-ghost, raft-player-faster, raft-c0150 and the speed, ghost, touch and radar preps). f0125 still only depends on c0153 and edits none of the five.

### F1 [high] `roundTrip` is never shown to compare what came back: a `roundTrip` that ignores the decoded value passes AC1 and AC3
Where: Design `plain.roundTrip` ("then `equalWithin(serde.decode("json", serde.encode("json", v)), v, eps)`"); plain.spec (every `roundTrip` case expects `true`, or `false` from `check` or the encoder); Rules and mutants (no row for it).
Evidence: in the clone, each mutant applied to `tests/lib/plain.luau`, then `lune run tests/run -- <plain.spec> <the five narrowed specs>`:
- Q1 `return plain.equalWithin(back, v, eps)` → `return plain.equalWithin(v, v, eps)`: `45 passed, 0 failed, 6 spec files`
- Q2 the same line → `return true, nil`: `45 passed, 0 failed, 6 spec files`
The only cases that reach the comparison ("one ulp off round-trips", "plain data is accepted") expect `true`, which a helper that never compares also returns. Yet the comparison is real and can fail: `plain.roundTrip({ ghosts = { { x = 13.783333333333333 } } }, 0)` → `false value.ghosts.1.x: 13.783333333333331 against 13.783333333333333`, and `plain.roundTrip({ x = 100000000.33333333 }, 1e-9)` → `false value.x: 100000000.33333331 against 100000000.33333333` (measured).
Critique: the round trip compared within a tolerance is the issue's whole point (its title); with Q2 the five narrowed specs check only that the frame is plain, and the "one ulp off" case proves nothing about the ulp. The tempting fix is a case on `equalWithin` alone, which P1 already has and which doesn't reach `roundTrip`.
Consequences: an `eps` of 0 is now a used input (it already is in the equalWithin case `{ x = 1 }, { x = 1 }, 0`); the reason's number text is `tostring` of a double, so assert its path prefix rather than the digits if Linux formatting is in doubt.
Recommendation: in "the value that came back one ulp off…", add `plain.roundTrip(frame, 0)` → `false` with a reason starting `value.ghosts.1.x: ` (this also pins E1, that the encoder really loses the ulp). Rules row: "roundTrip compares the decoded value with the original | plain :: one ulp off | Q1 compares v with itself, Q2 never compares | run".

### F2 [medium] A table reached twice without a cycle is refused by a plausible `walk`, and no case notices
Where: Design `plain.check` ("a table without a metatable or a cycle"); patch `walk` (`seen[v] = nil` after the children); plain.spec "plain data is accepted" (only distinct tables).
Evidence: Q3, delete `seen[v] = nil` (the marking never cleared, a common way to write a cycle check): `45 passed, 0 failed, 6 spec files`. With the intended helper, `local s = { x = 1 }; plain.check({ a = s, b = s })` → `true`, and `plain.roundTrip({ a = s, b = { s, s } }, 1e-9)` → `true` (measured): shared data is plain by the Design, and JSON writes it twice.
Critique: a frame that reuses a table in two places (the frame carrying the snapshot's ghosts list beside another view of it) is a natural future shape; with Q3 every one of the five specs would turn red with "a cycle" for a frame that replicates fine. The rule is in the Design's words and has no case.
Consequences: none beyond the case.
Recommendation: add to "plain data is accepted" `plain.check({ a = s, b = { s, s } })` → `{ true }` and its `roundTrip` → `{ true }`; Rules row "a table reached twice is not a cycle | plain :: plain data is accepted | Q3 seen never cleared | run".

### F3 [low] The absolute 1e-9 is below the encoder's error for non-integers above about 1e7, and the helper offers itself to every frame or snapshot spec
Where: Design Maintainability ("far above the encoder's error (about 4e-15 at 28 tiles)"); the helper's header; Design "One helper … for every frame or snapshot spec".
Evidence: `plain.roundTrip({ x = 100000000.33333333 }, 1e-9)` → `false` (off by 1.49e-8); `123456789.12345679` likewise (measured). Integers of any size round-trip exactly (`2^53 + 2`, `1e20`, `1729900000.123` all `true`). Today's five frames hold positions under 28 tiles and integer counters, so all pass.
Recommendation: state the bound where the next spec author reads it (the helper's header and Maintainability): the absolute eps holds for values under about 1e6; a spec with larger non-integers (a wall-clock time) needs a larger eps. No behaviour change.

### F4 [low] The Design's "every other JSON use" list misses `tests/lib/sim.luau`
Where: Design "Every other `serde.decode("json"`/`serde.encode("json"` under `pickman/tests` is … (c0003, c0010, c0015, c0051, c0064, f0026)".
Evidence: `git grep -nE 'serde\.(de|en)code\(\s*"json"' origin/main -- pickman/tests pickman/src | cut -d: -f2 | sort | uniq -c` lists also `pickman/tests/lib/sim.luau` (3: line 79 a debug `describe` of a table, 172 writing a replay file, 387 reading one). None is a round trip of game data compared exactly, so the conclusion stands; the list is incomplete.
Recommendation: paste this search with its file counts and name sim.luau's three uses as excluded (replay files and a debug description).
Lesson: zz-review/lists-paste-their-search

### F5 [low] The widening is recorded in Design and Guesses, not as a Scope decision line in the Problem
Where: Problem (still only "f0032's frame spec …"); Design "Scope."; Guesses 1.
Evidence: `./zn capture c0153` Problem names f0032 alone; z-design ("Scope is what was captured") says the user's answer is recorded "in the Problem as `Scope decision (user, YYYY-MM-DD): "<their words>"`". The current Problem reads as an f0032-only chore while AC2/AC3 cover five files.
Recommendation: append to the Problem `Scope decision (user, 2026-10-26): "Widen to all five"` (f0013 snapshot, f0018, f0030, f0032 frame, f0100 drops; design review 001 F2).

Lessons pass (`./zn lessons --when design --full`, 111 lessons): narrowing-pins-the-whole-file holds (whole text, no whitespace collapse, join mutant, base blobs, step 0); run-each-sequestered-spec-against-a-prototype holds on today's main (above); narrowing-exactly-to-at-least holds (the old exact compare caught nothing the within-eps compare plus `check` misses, except drift under 1e-9, which is the point); spec-design-correspondence fails for F1 and F2. The three lesson notes added this round (lists-paste-their-search, narrowing-pins-the-whole-file, split-paths-still-need-renamed-id) are each a rule another raft can fail, not restated findings. `./zn lessons --uncovered c0153` and `--check` pass. Repository safety: the specs only read files; `mutants.py` clones into `$TMPDIR` and refuses writes outside it. No tripwire fired.

Candidate lesson (for the lead): z-design/spec-design-correspondence — a helper that "does A, then compares B" needs a case where only the comparison can make it fail; check: for each function whose result every case expects to be `true`, is there an input for which the intended code returns `false` at the step the Design names?

Verdict: changes
