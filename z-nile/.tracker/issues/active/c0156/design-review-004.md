# Review 004: c0156 (design mode)
Inputs: prep worktree `prep-whole-file-pins-keep-newlines` at c5ab507a plus its uncommitted prep files (sha256 prefixes: `c0156.md` f0b58b04, `check.sh` c79b752f, `acceptance/consumers.luau` 1659eb46, `docs.spec.luau` 6b886c24, `kills.luau` 11b1ae54, `pin.spec.luau` b5258341, `record.luau` 5e9e63a4, `scripted.luau` 2bc130e7, `experiments/mutants.py` 7ba30eb8, `prototype.patch` ba4d71e7, `E9-comment-ends.luau` 97ef8127). I also read `design-review-001..003.md`, `design-refute-001..003.md` and `harvest.md`, and printed `./zn capture c0156` (capture 3bf887d6). origin/main is ec5c869b, and all eight base blobs the Design lists still match it.

The prototype is the clone `…/tmp.fipPiC5Jjp/proto` (base 0d4323b4). Its `check.sh` and acceptance folder are byte-identical to the worktree's (`cmp`). Every run below was made there, with `PICKMAN_FENCE_REAL_GIT` set and a time limit. I saved copies of `golden.spec`, `narrowed.spec`, `f0014/keys.spec` and `f0024/adapter.spec` to my scratchpad, edited them for the attacks, and copied them back afterwards. `cmp` against the saved copies matches, `git diff` of `f0014` is empty, and `git status --short` is back to its 10 entries.

Runs:
- `kills.luau` as check.sh runs it: all pass, 4.9 s (250 mutants).
- `mutants.py … kills-probe-pin-f0024 kills-fixed-mutant-set record-guard-warns-only consumers-forwarder-shadowed`: all killed, `OK`.
- A pin that compares shapes, not content (F1).
- A changed pinned file with its digest recomputed (F2).
- `luau.load` escape probes in the scratchpad (F3).

Scope: every outcome in the capture has a Design and a Checked criterion:
- c0103's pin keeps line breaks;
- the digests are recomputed;
- a comment-join mutant is killed by each pin;
- one shared normaliser;
- the record entry.

The `Decided with the user (2026-10-25)` line adds the CRLF-safe join (AC1, AC3). The prep's Non-goals bullet on exact-text pins only adds detail. One gap is F2: the Solution says the digests are "recomputed on the current files", but nothing checks that the files are still the current ones.

Earlier answers:
- **Round 001.** F2–F8 hold.
- **Round 002.** F2–F6 hold.
- **Round 003, F2 to F4.** These hold:
  - F2: record.luau checks the exit code, stdout, a one-line stderr and the absence of a traceback, and `record-guard-warns-only` is killed in my run.
  - F3: the names are fixed, and the fixture is now `{TOP}/z-nile/.cache/c0156-record`.
  - F4: the forwarder must have exactly one code line, and `consumers-forwarder-shadowed` is killed.
- **Round 003, F1.** The derived mutants close the "published list" attack. `kills-probe-pin-f0024` and `kills-fixed-mutant-set` are both killed. But the mechanism has a fourth hole, F1 below.
- **New rule from round 003.** "A record entry that is not in the file fails the check" has no Rules row. It is low and redundant, because record.luau's "occurs once" check reds the same entry, so I do not raise it as a finding.

### F1 [high] Every mutant kills.luau derives changes the file's line count, so a pin that checks only the normalised line count and the `t.expect(` count passes all of check.sh, while an assertion commented out in place, or turned vacuous, is not pinned (repeat of design-review-003 F1, fourth hole in the same mechanism)
Where: `acceptance/kills.luau` `generated` (lines 112–131) and the self-test (lines 133–195); c0156.md, the Design's `kills.luau` paragraph, AC7, and the Rules rows "a pin's verdict is wired … against every derived mutant".
Evidence: `generated` makes two kinds of mutant:
- a deleted line, which removes a line;
- a join of two lines, which also removes one.

The record's join entries are joins too. So every mutant kills.luau runs has one line fewer than the file. Golden's own mutant cases use `pin.joined`, which removes a line, and `pin.without`, which keeps the line but removes a `t.expect(`.

On the prototype I replaced the three verdicts with shape checks and left every case, constant and helper call as it was. The normalised line counts are 373, 986 and 40; the `t.expect(` counts are 44, 149 and 5. Here is golden.spec's version (narrowed.spec's `exactly` was changed the same way, with 40 and 5):
```luau
local function shape(text: string): (number, number)
	local n = pin.normalise(text)
	local _, lines = string.gsub(n, "\n", "")
	local _, asserts = string.gsub(n, "t%.expect%(", "")
	return lines, asserts
end
local function exactly24(text: string): boolean
	local l, a = shape(text)
	return #pin.digest(text) == #D24 and l == 373 and a == 44
end
```
Results with those pins:
- `narrowed.spec` and `golden.spec`: `9 passed, 0 failed`;
- `kills.luau`: `all checks passed` (all 10 + 62 + 176 mutants "rejected");
- `consumers.luau`: `all checks passed` (the require, `pin.digest(` and `pin.joined(` are all still there).

AC1, AC4 and AC5 never run a pin, and AC3 and AC6 run these same pins, so `./zn check c0156` would be 7/7.

Then, with the shape pins still in place, I made two edits to f0024:
- `t.expect(updates).toBe(6)` became `-- t.expect(updates).toBe(6)`. That is the captured hole itself: an assertion turned into a comment, here without a join.
- `t.expect(#names).toBe(if …)` became `t.expect(true).toBe(true)`.

`golden.spec` still gave `5 passed, 0 failed`. With the real pin restored, the same edits give `3 passed, 2 failed`.

The weakening is no more contrived than round 001's length compare. A pin of two numbers is a plausible "simplification", and kills.luau, the check built to catch weakened verdicts, accepts it. The c0103 header claim "the require lines are pinned, so a stub for View or Movement must not pass" is also unchecked by kills: no mutant touches a `require` line.

Critique: this is the fourth round in which kills.luau's mutant family left one property of the file unvaried, and a verdict that measures only that property passed:
1. round 001: a compare of lengths;
2. round 002: a weakened compare whose own mutant case was also deleted;
3. round 003: a fixed, published list of mutants;
4. now: the line count, plus a token count.

The tempting fix is to add "comment out each assertion in place". It would kill this pin but not the next one, which also compares the text's length or its character counts.

Consequences: the family must vary content while keeping every cheap statistic: line count, length, the count of each token, and the multiset of characters. Only a compare that is sensitive to position and content can kill such a mutant. In practice that means a digest of the whole text, which is what AC7 means by "pinned whole". The cost grows with the number of lines mutated. One kills.luau mutant run costs about 20 ms today (4.9 s for 250 mutants).

Recommendation: question the mechanism, not just this hole. AC7's family should be defined by what it holds fixed, not by which edits it lists. Two families:
- **Comment out each assertion line in place**, by prefixing `-- ` to each `t.expect(` line. This is the captured hole without a join, and it keeps the line count.
- **One same-length, same-characters edit on each non-blank line.** Swap two adjacent, distinct, non-space characters, so the line count, length, token counts (as far as the swap allows) and character multiset all stay the same.

The second family is 38 + 356 + 933 ≈ 1,330 mutants, about +27 s at today's cost. A cheaper variant mutates only the assertion, comment and `require` lines (≈ 265 mutants, about +5 s). It leaves a pin that hashes only those lines able to pass. If the cost is too high, say which variant you chose and why in the Design; that is a cost decision, not a scope cut.

Add to the self-test a synthetic `SHAPE` pin: the line count, the text's length and the `t.expect(` count. Some generated mutant must get past it, the way the `PROBE` pin is checked now. That way kills.luau going back to line-removing mutants only is red.

Rules rows and runner entries:
- `kills-shape-pin` (the attack above, on all three verdicts);
- `kills-no-in-place-mutants` (the generator without the new families).

Update E6/E8 with the new counts and times, and AC7's label ("every assertion line commented out, and one in-place edit of every line, derived from the file's text").
Lesson: zz-test/narrowing-pins-the-whole-file, zz-test/seed-every-enumerated-case

### F2 [high] Nothing checks that the pinned files are unchanged, or that the digests are the ones prep computed, so changing f0014's `keys.spec` and recomputing `DIGEST` passes check.sh while c0103's narrowing is lost
Where: c0156.md:
- the Chore checklist ("no pinned file changes");
- the Design ("`DIGEST = "ed27eb8b…"`, … (unchanged bytes)"; c0128's digests "stay as they are");
- Implementation step 0 (it checks the base blobs only at the start).

`kills.luau` lines 197–203 and `consumers.luau`; the capture's Solution ("with their digests recomputed on the current files").
Evidence: every check derives the expected verdict from the file as it is now:
- kills.luau: "passes on the files as they are";
- AC3: the pin's "exactly" case;
- AC6: c0103's and c0128's checks.

None of them fixes the digest values. On the prototype I deleted line 29 of `f0014/keys.spec.luau` (`t.expect(View.action(key)).toBe(nil)`, the "other keys do nothing" pin c0103 keeps). I then put the new `pin.digest` of the file (`825551fe…`) into `narrowed.spec` as `DIGEST`. Results:
- `narrowed.spec` + `keys.spec`: `7 passed, 0 failed`;
- `kills.luau`, `consumers.luau`, `record.luau`: `all checks passed`;
- c0103's `check.sh`: `3/3 criteria passed`.

The same holds for f0024 or f0026 together with `D24`/`D26` (c0128's titles and guards probes catch only some edits). This chore is the one change that rewrites c0103's pin and its digest. It is therefore the moment when the digest guards nothing, unless c0156's own check fixes the value. Step 0 checks `origin/main`'s blobs before the work starts. It does not check the branch's files at the end, and a careless executor's stylua run or an accidental edit would leave the files changed with a matching digest.
Critique: the Design states the right values (`ed27eb8b…`, `7f791c55…`, `744eeb0f…`) but only in prose. The tempting fix is a check that the three files are unchanged against `origin/main`. But git reads from a check.sh-only script compare against a moving ref (z-design/exact-checks-compare-against-the-merge-base), and a later narrowing of f0014 on main would turn this check red for a reason that has nothing to do with c0156.
Consequences: pinning the constants ties c0156's check.sh to today's bytes (modulo the tolerances). That is what the Design promises. It means a later narrowing chore of f0014/f0024/f0026 must name c0156's check in its Overrides, as it already must name c0103's or c0128's. Write that sentence into the pins' headers and the Design's "a later change to a pinned file" sentence.
Recommendation:
- **Pin the digests (check.sh check).** In `consumers.luau`, or a new check, assert that each pin's digest constant is the full 64-hex value prep computed. That is `DIGEST` in narrowed.spec and `D24`/`D26` in golden.spec. Also assert that `pin.digest` of each pinned file equals that value, so the file and the constant cannot move together.
- **Rules row and mutant.** Add a row `digest-recomputed-on-a-changed-file`: delete an assertion line of f0014 and recompute `DIGEST`. It must be killed by the new check, not by kills.luau.
- **Label.** Say in AC2's label (or a new AC) that the pins hold the digests of the files as prep pinned them.
Lesson: z-design/spec-design-correspondence (a stated value with no check). Candidate below.

### F3 [medium] kills.luau runs the executor-written pins outside the jail, and its "any other require raises" sandbox can be bypassed with `getfenv(0).require`; the Guards bullet does not say either
Where: `kills.luau` lines 59–78 (`luau.load` with `environment = { require = … }`); c0156.md, the Design's `kills.luau` paragraph ("any other require raises") and the Chore checklist **Guards** bullet (it names only the record's unjailed runs).
Evidence: check.sh runs `lune run "$A/kills.luau"` itself, outside `tests/run`. zz-test's "Caught only by review: `check.sh` files' own commands" applies. kills.luau `luau.load`s and runs every case of `narrowed.spec` and `golden.spec`, which the executor writes, in that unjailed process. Lune's `luau.load` injects the globals by default.

A scratchpad probe loaded this chunk with the same `environment = { require = <raising> }`:
```luau
return getfenv(0).require
```
It returned the real `require` (`function: 0x…`, `pcall` ok), and so did `getmetatable(getfenv(1)).__index.require`. So a pin can reach `@lune/process` or the real `@lune/fs` while kills.luau runs it, and nothing jails that.

The same reach lets a pin detect the harness (for example `fs.writeFile == nil` on the fake fs) and give kills a sound verdict and the runner a weak one. That is deliberate, but it is exactly what a code reviewer would have to spot. Reading the pins as "jailed specs", the reviewer has no pointer to this.

With `injectGlobals = false` and an explicit environment, the same probe fails (`attempt to call a nil value`), and `require` is the injected one.
Critique: the tempting fix is to add one more sentence to Guards. That leaves the Design's containment claim false, and leaves an escape any pin can take.
Consequences: with `injectGlobals = false`, kills.luau must supply every global the pins and `t` use (`string`, `table`, `math`, `pcall`, `error`, `tostring`, `type`, `select`, `ipairs`, `pairs`, `setmetatable`, …). A pin that uses one it does not supply raises inside the case. That is a false red unless kills.luau names the missing global in a FAIL line, separate from "not killed".
Recommendation:
- **Load with `injectGlobals = false`.** Use an explicit, listed environment, plus a check that the unmutated pins run with it.
- **Self-test.** Add a synthetic pin that calls `getfenv` or reads a global outside the list. It must fail to run, not be counted as a pass.
- **Rules row.** Add `kills-globals-injected`: kills.luau with `injectGlobals` left on, killed by that self-test.
- **Guards bullet.** Say that check.sh runs the two pins' code outside the jail inside kills.luau, with a read-only fake `@lune/fs` and no other module, so the code review reads the pins for that.
- **Design.** Correct the Design's "any other require raises" sentence to match.

Lesson candidates (for the lead):
- "A black-box kill check's mutant family must keep every cheap statistic of the text fixed (line count, length, token counts), with an in-place same-length edit of each line, or a verdict that measures only that statistic passes it. Check: replace the verdict with the line count plus the count of each kind of line the generator touches: does the kill check go red?" (c0156 design review 004 F1)
- "When a check takes its expected value from the file as it is (the pin passes on the current file), something must also pin that value: the constant prep computed, asserted by a sequestered check. Otherwise the file and its pin can change together. Check: change the pinned file and recompute its constant: does a check go red?" (c0156 design review 004 F2)
- "Code a check.sh-only script loads and runs (`luau.load`) runs unjailed. Give it an explicit environment (`injectGlobals = false`), and name it in the Guards bullet. Check: can the loaded chunk reach `getfenv(0).require`?" (c0156 design review 004 F3)

Verdict: changes
