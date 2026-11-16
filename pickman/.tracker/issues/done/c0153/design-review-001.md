# Review 001: c0153 (design mode)
Inputs: prep-frame-roundtrip-tolerance ee79fe42 (c0153.md, check.sh, acceptance/plain.spec.luau); prototype `.worktree/proto-c0153` (base eb2894eb, uncommitted: `pickman/tests/lib/plain.luau`, the f0032 hunk, `tests/acceptance/c0153`, identical to the prep's acceptance folder); `./zn capture c0153` (d00df6eb); f0125 / R0054 on origin/main (depends_on c0153). Experiments in a scratch clone (eb2894eb + the prototype's files) under `scratchpad/dr-c0153/repo`, and `scratchpad/dr-c0153/e1.luau` against the prototype's `plain.luau`.

Scope fidelity: the capture's Problem (f0032's exact JSON compare fails one ulp off) is kept, has a Design (the helper, the narrowed case) and AC2. No Scope decision needed. Tolerance: 1e-9 *absolute* is right for this frame: positions are at most ~28 tiles (encoder error ~4e-15 there, E1), a meaningful move is ≥ 1/120 tile, and every other number in the frame (tick, jumpTick, score, shots) is an integer, which an absolute 1e-9 can't blur (Luau has one number type, so "an integer becoming a float" can't be seen and isn't a defect: `{"x":-0.0}`, `9007199254740992` and `1e+300` all round-trip). A dropped or added key fails both ways (`value.a: missing on the left`), a changed type fails, a function/thread/metatable/cycle/NaN/inf fails `plain.check` first. So the tolerance itself hides nothing; the holes are in what pins the narrowed file and in two edges of the helper.

### F1 [high] The narrowed f0032 file is not pinned: deleting any of its assertions, or ignoring the round trip's result, or widening the tolerance passes every c0153 check
Where: acceptance/plain.spec.luau "f0032's frame case uses the helper…" (two `string.find` probes); check.sh AC2; Design "the case's other assertions … stay"; Implementation steps.
Evidence: in the scratch clone, each mutant applied to `tests/acceptance/f0032/frame.spec.luau`, then AC2's own command (`lune run tests/run -- tests/acceptance/c0153/plain.spec.luau tests/acceptance/f0032/frame.spec.luau`):
- M1 delete `t.expect(frame.ghosts).toEqual(snap.ghosts)` → `14 passed, 0 failed`
- M2 `plain.roundTrip(frame, 1e9)` → `14 passed, 0 failed`
- M3 `-- error(why)` (result computed, never asserted) → `14 passed, 0 failed`
- M4 delete `t.expect(g.jumpTick > resetTick).toBe(true)` in the tunnel/reset case → `14 passed, 0 failed`
- M5 `< 700` → `< 70000` → `14 passed, 0 failed`
The probe `plain.roundTrip(frame` matches any eps and any use of the result; AC2 then runs whatever f0032's file has become. The executor edits this promoted file (it's the Override), so it is exactly the file a hurried edit weakens.
Critique: this is the defect the lesson names. The tempting fix is a third probe for `1e-9` and one for `error(why)`, which still lets M1, M4 and M5 through and still pins private spellings.
Consequences: a whole-file pin ties execution to prep's base of f0032's file: if main edits it first (f0125 is rafted behind c0153 but other preps may touch f0032), the pin can never pass and the executor may not edit it. And a whitespace-collapsing digest lets a line be joined onto a comment unseen.
Recommendation: pin the whole narrowed file as c0128's `golden.spec` does: the exact text (LF line endings, no whitespace collapse) of the intended f0032 file, as a golden or digest, plus a case that the base blob of f0032 at execution equals the one prep cut from (recorded sha), and an Implementation step 0 "check f0032's blob is <sha>; if it moved, stop and re-prep". Mutants in the Rules table and run: M1–M5 above, and "join an assertion onto the comment above it". The two `string.find` probes can then go (lesson source-pins-name-what-the-design-names: a pin the golden covers only forbids correct idioms).
Lesson: zz-test/narrowing-pins-the-whole-file

### F2 [medium] The Regression guard's "no other spec uses the exact JSON compare" is false: four more promoted specs round-trip a snapshot or frame exactly
Where: Regression guard, second bullet; Maintainability ("one helper … reusable by any frame or snapshot spec").
Evidence: `git grep -nE 'serde\.decode\("json", serde\.encode' -- pickman/tests` at ee79fe42:
```
pickman/tests/acceptance/f0013/snapshot.spec.luau:41:		t.expect(serde.decode("json", serde.encode("json", snap))).toEqual(snap)
pickman/tests/acceptance/f0018/frame.spec.luau:86:		t.expect(serde.decode("json", serde.encode("json", frame))).toEqual(frame)
pickman/tests/acceptance/f0030/frame.spec.luau:123:		t.expect(serde.decode("json", serde.encode("json", frame))).toEqual(frame)
pickman/tests/acceptance/f0100/drops.spec.luau:193:		t.expect(serde.decode("json", serde.encode("json", frame))).toEqual(frame)
```
The design's search (`serde.decode("json"`) matched only the two-line form in f0032 because the others put `serde.encode` inline. f0100's case builds its session with `Session.GAME_CONFIG` (ghosts in the frame) at tick 0; it is green today only because no ghost has moved off a tile. Any later change that puts a ghost between tiles at the frame's tick (a start offset, another speed) turns it red for the same one-ulp reason.
Critique: the guard records a false fact, and the next prep that hits one of these will trust it. Widening the chore to these four is not a cut, but it is beyond the capture's wording (f0032 only), so it is the user's call.
Consequences: narrowing four more promoted specs means four more Overrides and four more whole-file pins (F1), each with a base check; leaving them means a known latent red.
Recommendation: replace the bullet with the search above and its four hits, each with why it is green today; then escalate to the user: (a) keep c0153 to f0032 and capture a chore for the four (cheap, the latent red stays until it lands), or (b) widen c0153 to all five (four more Overrides and pins). Either way say it in the Regression guard.
Lesson: zz-review/lists-paste-their-search

### F3 [medium] `equalWithin` treats NaN as equal to any number, and a NaN eps as "everything equal"
Where: Design, `plain.equalWithin`; prototype `plain.luau` `if math.abs(a - b) > eps then`; plain.spec has no NaN case for equalWithin.
Evidence: `scratchpad/dr-c0153/e1.luau`: `plain.equalWithin(0/0, 5, 1e-9)` → `true nil`; `plain.equalWithin(1, 2, 0/0)` → `true nil`. `roundTrip` is protected only because it runs `plain.check` first; the design offers `equalWithin` to "any frame or snapshot spec", where a NaN produced by a bug compares equal to the expected position.
Critique: the comparison is written so that every comparison with NaN takes the "equal" branch. The tempting fix (`a ~= a` → false) misses the NaN-eps case.
Consequences: none beyond the two cases.
Recommendation: compare as `if not (math.abs(a - b) <= eps) then` (NaN and a NaN eps both fail), state "NaN is never within eps" in the Design, add cases `equalWithin(0/0, 0/0, EPS)` false, `equalWithin(0/0, 5, EPS)` false, `equalWithin(1, 2, 0/0)` false, and a Rules row with the mutant `> eps` (the prototype as written).

### F4 [medium] `plain.check` calls array holes, sparse and number-keyed maps, and mixed tables "plain"; for number keys `roundTrip` then raises instead of returning false
Where: Design, `plain.check` ("a table … whose keys are strings or numbers"); `plain.roundTrip`'s contract `(boolean, string?)`.
Evidence: `e1.luau` against the prototype:
- `{1, nil, 3}`: check `true`, encodes `[1,null,3]`, roundTrip `true` (a hole passes everything; Roblox remotes drop what follows a nil in an array).
- `{[1]="a",[3]="b"}`: check `true`, roundTrip `false value.3: missing on the left`; `{1, 2, a = 3}`: check `true`, roundTrip `false value.a: missing on the left` (caught only by the round trip, but `check` itself is wrong).
- `{[2]="x"}`, `{[0]="x"}`, `{[-1]="x"}`, `{[1.5]="x"}`: check `true`; roundTrip **raises** `deserialize error: invalid type: integer \`2\`, expected a string key` (out of `serde.encode`), so f0032's `if not ok then error(why)` is never reached and the message is serde's, not a path.
Critique: the Design says the case now proves "plain data, more strictly than before", and the helper's header calls it "plain data, as replicated frames are"; holes and number-keyed maps are the classic Roblox replication losses, and the helper waves them through.
Consequences: a stricter `check` must still accept the frame's real shapes (the ghosts list, empty tables, which encode as `{}`/`[]`) — run f0032 and the full gate on the prototype again.
Recommendation: in `check`, a table is either an array (number keys exactly 1..n, no other keys) or a map (string keys only); refuse anything else with its path (`value.ghosts: a hole at 2`, `value: a number key 1.5 in a map`). Cases: hole, sparse, zero/negative/fraction key, mixed table, each refused by `check` and by `roundTrip` (returning false, not raising); the empty table accepted. Rules rows with mutants "accept a hole" and "accept a mixed table".

### F5 [low] "and says where" is not checked
Where: plain.spec "check refuses … and says where" asserts only `type(why) == "string"`.
Evidence: a `check` returning `false, ""` for every bad value passes the case; the Design promises paths such as `value.ghosts.1.x: inf is not a finite number`.
Recommendation: assert the path prefix for two of the bad values (`value.f`, `value.self`), or drop "and says where" from the case name.

Verdict: changes
