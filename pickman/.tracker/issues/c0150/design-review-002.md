# Review 002: c0150 (design mode)
Inputs: prep worktree at fce5a712 plus the uncommitted c0150 folder (c0150.md, check.sh, acceptance/narrowed.spec.luau, experiments/narrowing.patch, experiments/mutants.py, design-refute-001.md, harvest.md) and the two zz-test lessons (narrowing-keeps-each-members-check.md, new; narrowing-pins-the-whole-file.md, sharpened); f0126.md and its acceptance/adapters.spec.luau in prep-risky-wall-picks; the prototype's `src/` in proto-risky-wall-picks; f0110 in prep-touch-fire-and-hop and proto-f0110; `./zn capture c0150`. Everything was run in a `git clone --no-hardlinks` under `$TMPDIR` with the folder copied in and the patch applied.
Dropped from design-review-001: F1, F2, F3 (each fix is right; rulings below). F4 is fixed except for one row (F2 below).

Rulings on design-refute-001:
- F1 (fixed, accepted): the `want` loop asserts `View.KEYS[key]` as well as `View.action(key)`. `mutants.py` K1 (another `View.KEYS` table): killed; N11 (that line dropped): killed by the digest.
- F2 (fixed, accepted): an extra key's action must be in no `taken` slot and not a movement intent; the second case still forbids `"Snap"` in `View.KEYS`. `View.Action` is a closed union (`View/init.luau:14-22`), so with these two checks an extra key can only bind a new member of it, as f0126's `"Pick"`. I ran extra keys in the clone against the narrowed `keys.spec`: `F = "Fire"`, `F = "Snap"`, `F = "LookUp"`, and `F = "Fire"` beside `G = "Pick"` each gave `3 passed, 1 failed`. The second case's title ("only W A S D are movement intents") is true of the file again.
- F3 (fixed, accepted): the digest is now of the exact text, with only CRLF made LF and `[fdcR]<digits>` ids masked. The masked tokens in both files are only in comments and the two `t.spec` titles (grep in the clone), so the mask cannot hide a code change. N9 and N10 are killed.
- F4 (mostly fixed): K1 to K4 cover the `want[key]` loop, `n == 10` and the `%)`; the removed `"F"` has no row (F2 below).

Confirmed and not findings:
- `python3 …/experiments/mutants.py`: all 15 rows `killed`, none `LOAD ERROR` or `ANCHOR`.
- With the patch: `narrowed.spec` plus the two narrowed specs `12 passed, 0 failed`; `stylua --check` clean on all three; `./zn check c0150` 3/3; `z-nile/check.sh --project pickman --full`: types clean, `1404 passed, 0 failed, 206 spec files`, GATE PASSED.
- E2: with the prototype's `src/` copied into the clone (F = "Pick", `Hop.rise(hopped, shown, hopTicks)`), the same three files give `12 passed, 0 failed`.
- The third `Hop.rise` argument the narrowed pattern now allows is pinned by f0126 (`adapters.spec.luau:54`, `…Hop%.rise%(%s*hopped%s*,%s*[%w_]+%s*,%s*hopTicks%s*%)`, and `Camera.hopTicks(frame.hopTicks)` at :60), and f0126 has `c0150` in `depends_on` and names both files in its Overrides line.
- Controls binds only `View.KEYS` names (`Controls.luau:82`) and dispatches through `View.action`, so a key `View.action` maps but `View.KEYS` lacks is never bound: the narrowed spec's per-key checks are on the table that matters.
- Other in-flight work: `grep -rlF -e f0104/keys.spec -e f0101/place.spec --include='*.md' .worktree` (outside c0150, f0126 and `done/`) finds only f0110, which records `Overrides: none`, and proto-f0110's Camera still calls `Hop.rise(hopped, shown)`.
- Scope: title, Problem and Solution match the capture (9cbf93c4); every outcome has AC1 to AC3. The extra-key constraint adds detail; it removes nothing f0126 needs.

### F1 [low] The sharpened lesson's "How to apply" still tells authors to normalise whitespace as c0103 does
Where: z-nile/skills/zz-test/lessons/narrowing-pins-the-whole-file.md, the "How to apply" paragraph ("normalise the file as `tests/acceptance/c0103/narrowed.spec.luau` does (whitespace, a trailing comma, ids masked, comments kept)")
Evidence: the paragraph this prep adds at the end says the opposite ("Normalising whitespace is not harmless … Pin the exact text"), but the instruction an author follows first is unchanged, and it names whitespace collapse as the method. A later narrowing chore that follows "How to apply" rebuilds round 1's F3 defect.
Critique: the fix sits in a postscript, while the lesson's instruction still gives the old method.
Consequences: pointing at c0150's spec as the model means the c0103 mention becomes "known gap, not exploitable today" rather than the template.
Recommendation: rewrite "How to apply" to pin the exact text (ids masked, CRLF made LF, nothing else), cite `tests/acceptance/c0150/narrowed.spec.luau` (its path after promotion) as the model, and move the c0103 mention there as a known gap.

### F2 [low] Rules and mutants has no row for the removed `"F"` in the unbound list
Where: c0150.md Rules and mutants; design-review-001 F4 named `"F"` among the removed assertions needing a code-mutant row
Evidence: K1 to K4 cover the `want` loop, `n == 10` and the `%)`; no row says what the dropped `View.action("F") == nil` used to catch. I ran the candidates in the clone: `F = "Fire"`, `F = "Snap"` and `F = "LookUp"` added to `KEYS` are each killed by the narrowed `keys.spec` (`3 passed, 1 failed`). The one survivor, `View.action` mapping F while `View.KEYS` does not, is inert in the game, because Controls binds only `View.KEYS` names.
Critique: the behaviour is guarded; the record isn't, so the next reviewer must redo this.
Consequences: none.
Recommendation: add a row: rule "F may be bound only to an action of its own", case `f0104 keys :: maps the ten keys, and may map more` (and the Snap check in the second case), mutants K5 `F = "Fire"` and K6 `F = "Snap"` added to `mutants.py` and run. Note in E3 that a `View.action`-only binding of F is meant to survive, since Controls never binds it.

### F3 [low] AC1's check label says "more keys allowed" without the limit on them
Where: check.sh AC1 label "(the ten bindings, more keys allowed, F free; …)"; narrowed.spec case title "…more keys allowed, F free"
Evidence: the document's AC1 says "more keys allowed only with actions of their own", and the narrowed spec enforces that. The label reads as if any extra binding passes (z-design lesson spec-design-correspondence: "does every check's label say exactly what its command verifies").
Critique: someone reading only the gate output thinks the pin is looser than it is.
Consequences: none (the label is not part of the digest).
Recommendation: say "more keys allowed, each with an action of its own" in the AC1 label and in the narrowed spec's case title.
Lesson: z-design/spec-design-correspondence

Lesson candidates: none new. F1 is a defect in a lesson this prep sharpened; harvest it as a note on narrowing-pins-the-whole-file.

Verdict: approve
