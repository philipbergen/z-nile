# Review 007: c0458 (design mode)
Inputs: prep worktree `prep-collapse-reviews-and-tighten-caps` at 91ff6d91e with its uncommitted `z-nile/.tracker/issues/c0458/{c0458.md,check.sh,guesses.md,harvest.md,acceptance/{caps-modes,walk,docs,publish}.spec.luau,experiments/prototype.patch,design-refute-006.md}`; `design-review-006.md`. Checks made, every run through `./zn run`:
- `experiments/prototype.patch` (489 lines) applied to a `git archive 1b78199b0` copy in `.cache/c0458-r7-proto`, its own repository, with the four specs copied into its `z-nile/tests/acceptance/c0458r7`. The copy's commits took their identity from the environment (`@example.invalid`), no identity was written to any git configuration, and the copy is removed. origin/main is now c2dc2fc9a: since the base it changed tracker files and `z-nile/next` only.
- On that copy walk passes 5/5, publish 4/4 and caps-modes 4/4. docs fails 2/2 at `docs.spec:20` and `:41`, as before, because the copy holds today's skills.
- Six mutants of the prototype's `easy.raisedBy` against `walk.spec`, one at a time, each restored after its run. Five are red and one stays green (F1).
- Three of round 6's sixteen publisher mutants, spot-run: `now >= was` removed, an empty raise accepted and `raiseWhole` disabled are still red.
- `./zn promote-check c0458` inside the copy, with the current specs: no type error in c0458's four specs.
- `stylua --check` and `selene --quiet` on `z-nile/.tracker/issues/c0458/acceptance` (F3).
- `./zn capture c0458` compared with the document: Problem, Non-goals and Solution are still the capture's text.
- `./zn lessons --check`, `--uncovered c0458` and `--unattributed c0458` pass. The harvest lines for review 006 carry its step lines.

Round 6 answers. The refute file disputes nothing, so there is no refutation to accept or re-raise.
- F1 is fixed in the spec, the rows and item 10.
  - The three lines are at `walk.spec:194-196` and pass on the prototype.
  - Round 6's mutant 1 (any line of normal or risky raises a short-noted ticket) is red at `:194`, and its mutant 2 (the last line wins) is red at `:196`.
  - The two own-level mutants are still red (`:190` and `:191`), and "the lowest line wins" is red at `:196`.
  - Item 10 has the clause, and it agrees with the brief's sentence in the patch ("a ticket that needs a design review, Level: risky").
  - Two parts of the answer are not in the document: E5 has no record of the two mutants, and the reworded row kept the old mutant (F2). The line the recommendation gave pins one order of two (F1).
- F2 is fixed in two of its three parts.
  - The no-raise case is in the Test plan's IO bullet with both fixtures and the three expectations.
  - "Edited existing specs" names `light-path.spec.luau:1309`. "raised c0010 to normal" is what the patch's text gives for that fixture (an easy c0010 and `Level: normal`).
  - The run line's red half now names the empty-raise case. Its green half is unchanged, though the refute says it was changed (F2).

### F1 [medium] The new line pins "the highest line wins" in one order, and a reader that keeps a ticket's first line passes
Where: `acceptance/walk.spec.luau:196`; Rules row "the highest line wins per ticket"; Design item 10 ("per ticket the highest of normal and risky wins"); review-006 F1, the Recommendation's third line
Evidence:
- Line `:196` gives c0010 `Level: c0010 risky` and then `Level: c0010 normal`, and expects risky. A reader that keeps the first line it sees for a ticket also answers risky. No case gives one ticket a lower line and then a higher one.
- Mutant: in the patch's `easy.raisedBy`, `(out[ticket] == nil or RANK[word] > RANK[out[ticket]])` changed to `out[ticket] == nil`. `walk.spec`: "5 passed, 0 failed".
- What that reader does, read from the design and not run, because the prototype holds no `stop`: for an easy c0010 whose reviews hold `Level: c0010 normal` and then `Level: c0010 risky`, it answers normal. `stop` publishes `risk: normal`, the publisher accepts it, and the ticket needs no design review where a review said risky. This is the end state round 6 described for "the last line wins", with the lines in the other order.
- Today's reader has both orders pinned (`tests/tooling/easy-path.spec.luau:159` and `:160`). The new reader has one. That spec does not call `raisedBy`, and in the patch `easy.raised` is a separate loop.
Critique: round 6 recommended this one line and named one mutant for it, and the answer added exactly that. A rule that picks the highest of several lines needs a case in each order, or "first" and "highest" give the same answer. The tempting fix is to add "the first line wins" to the row's mutant column with no new line. Lesson candidate for zz-review: when a Recommendation gives spec lines for a rule that picks one of several (highest, first, last), does it give the lines in both orders, and was each run against the mirror mutant?
Consequences: none. The added line states no new rule: its value is what item 10 already says.
Recommendation:
- Add one line after `:196`: `t.expect((raisedBy({ "Level: c0010 normal\n", "Level: c0010 risky\n" }, high, none))).toEqual({ c0010 = "risky" })`. I ran it on the prototype as a probe: it passes there, and the mutant above turns it red.
- Change the row's mutant column to "the last line wins, or the first line wins", and record both runs in E5 (F2).
Erred: zz-review
Upstream: none

### F2 [low] Three records that round 6's answers needed are not in the document
Where: Test plan, the "Run result at prep" line; E5; Rules and mutants, the first of the two rows "a line below a ticket's own level raises nothing, short note or not"; refute-006 F1 and F2
Evidence:
- The run line. refute-006 F2 says the line now says "that AC4 passes on the prototype". Its green half still reads "(`experiments/prototype.patch`: rounds, models, `.models.toml`, dispatch, work, readycheck, easy): AC1 and AC2 pass; AC3 is red there". It names neither `publish` nor AC4.
- E5. The rows for "any line of normal or risky raises a short-noted ticket" and "the last line wins" say `run: AC8 red`. E5's list for walk AC8 still holds only the two own-level mutants. Round 6 asked for the red lines in E5, and a row marked `run` has its outcome there (zz-review, Design mode item 0).
- The reworded row. The old row "a line at or below a ticket's own level raises nothing" now states the below-level rule and kept its mutant, "a raise to the ticket's own level counted". The table then holds the below-level rule twice, and the first copy's mutant belongs to the own-level row, which already lists it as "counted for a full design".
Critique: this is the third refute file in a row with a claim the document does not hold (review-005 F4 and review-006 F2 found the others). E5 is what an executor who rebases the prototype reruns from, so a mutant missing there is a mutant not rerun.
Consequences: none.
Recommendation:
- Add `publish` and AC4 to the run line's green half.
- Add the mutants to E5's walk AC8 list with their red lines: any line raises a short-noted ticket (`:194`), the last line wins (`:196`), and F1's first line wins. Take the line numbers after F3's formatting.
- Delete the first of the two "a line below" rows.
Lesson: z-design/restated-rules-move-together
Erred: z-design
Upstream: none

### F3 [low] The four specs fail the gate's format check, round 6's new lines included, and one fails its lint
Where: `acceptance/walk.spec.luau:191-196` and the other three specs; `acceptance/caps-modes.spec.luau:83`; `z-nile/check.sh:287-288`
Evidence:
- `stylua --check z-nile/.tracker/issues/c0458/acceptance` exits 1 with a diff in all four specs. In `walk.spec` the diff rewraps `:196`, the line round 6's answer added (116 characters before its tabs are widened, against `column_width = 110`), and `:191`.
- `selene --quiet` on the same folder exits 1: `caps-modes.spec.luau:83:37: warning[shadowing]: shadowing variable level`. Round 6's edit did not write that line. The same static stage reads it.
- The gate's static stage runs both commands over `z-nile/.tracker` (`z-nile/roots --luau-dirs` lists it), so the prep pull request's static gate is red with the folder as it stands.
- The hook that formats a `.luau` file after an edit is Claude Code's only (zz-test, Hooks). A design written on another CLI has to run the format itself.
Critique: the repair is mechanical, but its order matters. Formatting after the last mutant run changes the files the mutants ran on and every line number recorded from them. The tempting fix is to format `walk.spec` alone.
Consequences: stylua moves lines, so the red lines E5 gains in F2 are read from the formatted files, and the specs and `./zn promote-check c0458` are rerun after it.
Recommendation:
- From the worktree's root run `stylua z-nile/.tracker/issues/c0458` until `stylua --check` on it is clean.
- Rename the parameter at `caps-modes.spec.luau:83` so it no longer shadows `level`, until `selene --quiet` on the folder exits 0.
- Then rerun the four specs and F1's mutant on the prototype, and `./zn promote-check c0458`.
Lesson: zz-test/format-tracker-specs-by-path
Erred: zz-test
Upstream: z-design

Verdict: changes
