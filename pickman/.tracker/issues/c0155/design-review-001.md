# Review 001: c0155 (design mode)
Inputs: worktree `prep-narrow-button-table-pins` at cb25beb0 plus its uncommitted c0155 files (shasum: `c0155.md` d8156e951907, `check.sh` 476a01424162, `acceptance/narrowed.spec.luau` e088266f2528, `experiments/mutants.py` 6912a86c85be, `experiments/E5-compaction.luau`); `./zn capture c0155` (capture e6397859, no marker); promoted `tests/acceptance/f0110/buttons.spec.luau`, `tests/acceptance/f0146/pad.spec.luau`, `.tracker/issues/done/{f0110,f0146}/check.sh`; d0149's prep doc (`.worktree/prep-touch-circle-controls/pickman/.tracker/issues/d0149/d0149.md`).

Runs (this round): `./zn check c0155` 2/2 PASS; the spec on its own 5 passed; `experiments/mutants.py` in a `--no-hardlinks` clone under `$TMPDIR`: BASE pass, M1–M8 all `killed`; E5 `before 3 3 / after old 0 0 / after new 3 3`; affected selector in the clone with the spec copied to `tests/acceptance/c0155/`: `pickman/tests/acceptance/f0110/buttons.spec.luau` and `pickman/src/shared/Logic/Touch` both select `tests/acceptance/c0155/narrowed.spec.luau`. Scope: the capture's outcomes (each case pins its entries one by one, added buttons pass, every entry pinned today stays pinned, the chore checks this) all have a Design and AC1; the dropped digest carries the user's `Scope decision (user, 2026-10-31)`. Overrides: none is right (no promoted spec changes; `git grep -lF tests/acceptance/c0155` hits nothing). F1 is about the third outcome.

### F1 [high] The "still fails" variants for f0110's case move only `x`, on every sample at once, so a case that pins one sample, or only `x`, passes AC1
Where: `acceptance/narrowed.spec.luau:103-105` (`moved`) and `:142-155`; Design, "must fail when any of `snap`, `fire` or `hop` is moved one pixel or removed"; Rules and mutants rows M2/M3.
Evidence: in the scratch clone, two weakenings of f0110's promoted case leave `narrowed.spec` green (each restored afterwards; `git status` clean):
- R1, insert `break` after `t.expect(b.hop).toEqual(T.hopRect(box))` (the case checks only the first of its 13 sample screens): `5 passed, 0 failed, 1 spec files`.
- R5b, each line becomes `t.expect(b.<name> and b.<name>.x).toBe(<rect>(box).x)` (y, w and h no longer pinned): `5 passed, 0 failed, 1 spec files`. (The plain `b.<name>.x` form, R5, is "killed" only through the missing variant's `attempt to index nil` error, i.e. by the non-assertion path, not by a real failure.)
The capture's outcome is "every entry it pins today stays pinned"; f0110's case pins each whole rectangle on every sample screen (the Design's own words: "for every sample screen"). Both weakenings drop pins and pass AC1.
Critique: the tempting fix is to add a `y` shift to `moved`. That still misses a case that drops `w` or `h`, and still misses R1.
Consequences: perturbing one sample at a time needs the spec to know how many samples the case walks. Counting calls from the identity run alone is not enough (under R1 the identity run makes 1 call, and moving call 1 fails, so R1 still survives). The count needs a floor, which pins today's sample set as a minimum; per zz-test/promoted-specs-pin-rules-not-sets it must be a floor (`>=`), not equality, so a later issue that adds samples stays green, and one that drops samples must name c0155 on its Overrides line (the Existing work paragraph already says this for d0149).
Recommendation: in the case "f0110's case still fails when the snap, fire or hop rectangle moves or is missing": (1) run the identity edit with a wrapper that counts `Touch.buttons` calls and assert the count `>= 13` (today's sample screens, comment saying a later issue may add more); (2) for each call index k in 1..count, each name in snap/fire/hop, and each field in x, y, w, h, run the case with only call k's `out[name][field]` changed by +1 and expect `false`; and with only call k's `out[name] = nil` and expect `false`. That is about 13 x 3 x 5 = 195 runs of a 13-layout case, cheap. Add Rules rows (run, in `mutants.py`): M9 `break` after the first sample (R1 above), M10 nil-safe `x` only (R5b above), M11 one field dropped (for example `h`) from one rectangle's compare. The f0146 variants need no change: `toBe` on a swapped real action and on nil already pins each entry.
Lesson: zz-test/seed-every-enumerated-case

### F2 [low] `passes` counts any error text containing "expected" as an assertion failure
Where: `acceptance/narrowed.spec.luau:63`.
Evidence: (read, not run) Luau's own argument errors contain the word, for example `invalid argument #1 to 'ipairs' (table expected, got nil)`; a case that errors that way on a removed rectangle counts as a clean "fails", and the "any other error fails this spec instead" rule in the Design doesn't hold for it. `t`'s messages all begin `expected ` right after the `file:line: ` prefix that `error(…, 2)` adds (`z-nile/tests/lib/t.luau:49-74`).
Critique: the tempting fix is a longer substring like `"expected "`; `table expected, got nil` doesn't match that, but other builtin messages could.
Consequences: an anchored pattern depends on `error(…, 2)` keeping its location prefix; if `t` ever changes its level, the anchor must change too.
Recommendation: match `string.find(text, "^[^\n]*:%d+: expected ")` (or `^expected ` as a fallback when the text has no prefix), and keep the "not an assertion failure" error otherwise. No new case needed beyond a comment; optionally a mutant row whose case indexes `ipairs(b.snap)` on a removed rectangle.

### F3 [low] "their check.sh files still run them" passes with the check line commented out
Where: `acceptance/narrowed.spec.luau:125-126`.
Evidence: in the clone, `sed 's/^check "AC1/# check "AC1/'` on `.tracker/issues/done/f0110/check.sh`, then the spec: `5 passed, 0 failed, 1 spec files`.
Critique: done items' `check.sh` files are sequestered and rarely touched, which is why this is low, but AC1 says they "still run them".
Consequences: none beyond the pattern.
Recommendation: look for a line that starts with `check "` and contains `"$A/buttons.spec.luau"` (iterate `string.gmatch(text, "[^\n]+")`, plain `find` for the path), and add the comment-out mutant as a `mutants.py` row (M12).

### F4 [low] `mutants.py` edits whatever path it is given, with no guard against the real checkout
Where: `experiments/mutants.py:3-6, 27-30`.
Evidence: it writes `tests/acceptance/f0110/buttons.spec.luau`, `pad.spec.luau` and `.tracker/issues/done/f0146/check.sh` under `sys.argv[1]` and only restores them after each run; the "clone under `$TMPDIR` only" rule lives only in the doc. An interrupted run against the worktree leaves a promoted spec mutated. It isn't a spec or a `check.sh`, so the runner never runs it, which is why this is low.
Consequences: none.
Recommendation: refuse unless `os.path.realpath(clone)` starts with `os.path.realpath(os.environ["TMPDIR"])` and `git -C clone rev-parse --git-common-dir` is inside the clone.

## Candidate lesson (for the lead)
- zz-test (narrowing / verify-a-narrowing chores): a spec that proves a promoted case still pins a value perturbs every field of that value, one loop element at a time, with a floor on how many elements the case walks; perturbing one field on every element at once lets a case that checks one element, or one field, pass. Check: for each value the case compares, does some variant change only one field of only one element, and does the spec fail if the case's loop stops early? (Close to zz-test/seed-every-enumerated-case; it could be a note there.)

Verdict: changes
