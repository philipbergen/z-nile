# Review 005: c0115 (design mode)
Inputs: `prep-c0115` at c8734a6; `design-review-004.md`, `design-refute-004.md`, rounds 001 to 003 skimmed, `harvest.md`; `c0115.md`, `check.sh`, `acceptance/*`, `experiments/rename-lesson-ids.luau` (all byte-identical to the prototype's); `z-nile/engine/lessons.luau` (`parseHarvest`, `ledgerLine`, `ledgerOldIds`, `renameLedger`) on `proto-c0115` at b0474ea (on bc550e9); `./zn capture c0115` (fb7fd80); `./zn lessons --when design --full`. Everything ran in a scratch clone of the prototype (`c0115-review005/ov` in the scratchpad), never in the repository. The setup: the prep tree's 34 lessons laid into their new folders; its five `harvest.md` ledgers, and the review and refute files they cite, copied in (c0120's under `done/c0120`); the prep's c0115 folder copied in; a baseline commit.
Dropped from review-004: F1 and F2 (fixed, checked below).

Re-review of round 004:
- F1: fixed. `ledgerLine` now sends every line `parseHarvest` returns no entry for, and every one-off line, through the prose rule as a whole. Only a parsed id list takes the id rule.
  - Overlay: 217 rewrites, exit 0. The count is 211 plus round 4's new harvest entries. A second run made 0.
  - Every rewritten ledger equals its old text with each `<old>/<slug>` token mapped, so the rewrite is a pure substitution. The seven lesson-body changes are correct renames.
  - `./zn lessons --check`: "34 lessons, 190 harvest entries, ok". `--uncovered R0040 R0042 c0115 c0120 R0043`: covered. `./zn skills --check`: ok.
  - AC3: `layout.spec` 7 passed and no `z-raft`. AC4: `absence.spec` 6 passed. AC5: `lessons.spec` 11 passed. AC6: passes.
  - Probes on R0042's ledger:
    - renamed: the heading, a paragraph, an indented sub-bullet, a note's text, and a refused line, which still fails `--check`;
    - left byte for byte: the look-alikes `review/x`, `tracker/rafts/R0010` and `testing/fixtures` in the paragraph.
  - Spot-run mutants against `lessons.spec`. M49 (skipped lines left alone) is killed by the every-byte case, and M50 (the note head not scanned) by the parsed-ids case. A third mutant survives (F1 below).
- F2: fixed. The intro and §11 name bc550e9 as the measured base, list what `impl-c0120` changed after it, and send Implementation step 1 to rerun §11.
- Scope (item 11): the capture is unchanged. The fix delta touches only §5, §11, E4, E5, the Rules table, the Verification log and the spec list. The title, Problem, Solution and Non-goals are untouched.
- Lessons (item 10): the two lesson notes this round are general rules another raft could fail: "a rule built on a reader covers the lines the reader skips", and "run the skipped checks before committing to a shared branch". Neither is a restated finding.
- Repository safety (item 9): no new command. AC2 still runs in a `.cache` clone.

### F1 [medium] No case gives a one-off's reason an old id whose renamed lesson exists, so "one-off lines left alone" passes AC5
Where: `lessons.spec` "a ledger's parsed ids all count; its notes and one-off reasons are prose…" (lines 146–200) and "every byte of a ledger is covered…" (line 204); §5 ("the rest of an entry's line (a note's text, a one-off's reason) … takes the prose rule"); the Rules table (M48, M50).
Evidence:
- The ledger has seven kinds of part. Six of them have a positive case (an old id whose renamed lesson exists, found and renamed): the id list, a note's text (M50), the heading, a paragraph, a sub-bullet and a refused line.
- The one-off reason has only look-alike cases (`one-off: a stale testing/fixtures link and a review/round path`, `one-off: a review/x path`), which a do-nothing implementation also passes.
- On the renamed overlay, `lessons.luau` was mutated to return a one-off line unchanged (`if entry and entry.oneOff then return line, 0, found, unknown end`). `lessons.spec` then gave 11 passed, 0 failed.
- The real-tree case can't catch it: no one-off reason in today's five ledgers names an old id.
- With the correct code, `- review-001 F2: one-off: see testing/no-vacuous-pass for why` is found (1 found, 0 unknown) and renamed to `zz-test/no-vacuous-pass`. So the rule works, but nothing pins it.
- This is the same mechanism as rounds 003 and 004: a part of the ledger whose coverage nobody planted.

Critique: §5 states the one-off rule, so a wrong implementation passes AC5 while it holds an outcome the Design promises. The tempting fix is one more planted line. That works, but the gap came from listing the cases by hand, the third round in a row.
Consequences: none beyond the case. Unknown-id reporting stays limited to parsed ids, so a one-off reason naming an old id with no renamed lesson must stay silent (exit 0).
Recommendation:
- Make the every-byte case a table, one row per part: id list, note text, one-off reason, heading, paragraph, sub-bullet, refused line. Each row is checked twice:
  - with `testing/no-vacuous-pass` (in `existing`): found by `ledgerOldIds` and renamed by `renameLedger`, with a count of 1;
  - with a look-alike (`review/x`, `testing/fixtures`): not found, and byte-identical.
- Add a one-off row naming `testing/never-a-lesson` (renamed lesson absent): `ledgerOldIds` returns no unknown, and the script's exit stays 0.
- Add mutant row M51, "one-off lines left alone", killed by the one-off row.
- Rerun E5's runner for M46 to M51.

Lesson: zz-test/seed-every-enumerated-case, z-design/spec-design-correspondence

### F2 [low] The ledger rename rewrites the separators of every id list on a line it changes, so "nothing else changed" holds only for `, `-separated lists
Where: `lessons.luau` `ledgerLine` (`return out .. table.concat(parts, ", ")`, and the head pattern `(.-)%s*$`); the script writes a file whenever its count is above 0.
Evidence:
- `- design-review-099 F1: testing/no-vacuous-pass,testing/absence-scans-cover-every-form` became `… zz-test/no-vacuous-pass, zz-test/absence-scans-cover-every-form`.
- Trailing spaces on an id-list line are dropped.
- In a file that has at least one rename, a no-space list on a line with no old id is normalized too, and the count doesn't show it.
- Today's ledgers all use `, `: the pure-substitution comparison above is identical. So nothing breaks now.

Recommendation: either rebuild the list by substituting each renamed id in place (`gsub` over the ids substring, with plain matching), or say in §5 that id lists are rewritten in the canonical `, ` form. Add one look-alike case: a no-space list with no old id comes back byte-identical.

### F3 [low] Two texts still describe the rule as it stood before round 4
Where:
- `c0115.md` E5 ends "(M1 to M45)" right after "50 on bc550e9 after round 4".
- `rename-lesson-ids.luau`'s header ("its notes and one-off reasons as prose") and the comment in `fix` ("the ids lessons.parseHarvest reads are ids; its notes and one-off reasons are prose") leave out the skipped and refused lines, which now take the prose rule as well.

Recommendation: E5 should say "(M1 to M50)". The two comments should match §5's wording: "every other part of a ledger is prose".

Verdict: changes
