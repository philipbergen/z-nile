# Review 004: c0115 (design mode)
Inputs: `prep-c0115` at df847d2 (c0120's prep merged in); `design-review-003.md`, `design-refute-003.md`, rounds 001 and 002 skimmed, `harvest.md`; `c0115.md`, `check.sh`, `acceptance/*`, `experiments/rename-lesson-ids.luau`; `z-nile/engine/lessons.luau` (`parseHarvest`, `ledgerLine`, `ledgerOldIds`, `renameLedger`) on the prototype `proto-c0115` at 5ba8ff4 (on `proto-c0120` bc550e9); `./zn capture c0115` (fb7fd80); `./zn lessons --when design --full`. Everything ran in a scratch clone of the prototype (`c0115-review004/ov` in the scratchpad), never in the repository. The setup: the prototype's lessons removed; the prep tree's 34 lessons laid into their new folders; its five `harvest.md` ledgers and the review and refute files they cite copied in (c0120's under the simulation's `done/c0120`); the prep's c0115 folder copied in; a baseline commit.
Dropped from review-003: F1, F2, F3 (fixed, checked below).

Re-review of round 003:
- F1: fixed as the refute says. The ledger rule now goes through `parseHarvest`.
  - On the overlay the script made 211 rewrites and exited 0. A second run made 0. The count is 203 plus c0120's newly merged entries.
  - `./zn lessons --check`: "34 lessons, 186 harvest entries, ok". `--uncovered R0040 R0042 c0115 c0120 R0043`: covered. `./zn skills --check`: ok.
  - AC3's `layout.spec` (7), AC4's `absence.spec` (6) and AC5's `lessons.spec` (10) pass, and AC6 passes.
  - I read the lesson-body diff line by line: seven correct renames, including the two lessons just merged from c0120 (`derive-after-stripping-overrides`, `guards-move-with-the-working-directory`).
  - Probes:
    - A note naming `review/x` is left alone.
    - A refused line (`- see testing/no-vacuous-pass`) fails AC6.
    - A note text containing `: ` splits where `parseHarvest` splits.
    - A one-off reason's prose is found inside the line, never inside its prefix.
  - The hole that remains is F1 below.
- F2: fixed. "reads the design skill and the zz-test skill" mixes a description with a name, but it is correct, and the refute said it would read that way.
- F3: fixed (the base is named by sha). See F2 below for the stack's movement since.
- Scope (item 11): the capture is unchanged. Since 5559d6b the title, Problem, Solution and Non-goals are untouched. G1 to G11 are as before, and each is still a reasonable guess.
- Lessons (item 10): this round's harvest adds no new lesson. It reuses two and sharpens `one-rule-one-function`'s check, which is a rule another raft could fail, not a restated finding.

### F1 [medium] The ledger rule skips every `harvest.md` line that isn't a bullet, so an old id in a ledger's free prose line passes AC5, AC6 and the script
Where: `lessons.luau` `ledgerLine` (`if not entry then return line, 0, {}, {} end`); §5 ("a line `parseHarvest` refuses is left alone, since `lessons --check` (AC6) already fails on it"); `lessons.spec`'s real-tree case.
Evidence:
- `parseHarvest` has two ways to pass a line over:
  - it *refuses* a `- ` line it can't read (a problem, so AC6 goes red);
  - it *skips* every line that doesn't start with `- ` (`continue`, no problem).
- §5's premise covers only the first. Skipped lines are a real shape: `rafts/done/R0042/harvest.md` line 2 is a prose paragraph ("Rounds 001 to 005 reviewed the reduced-scope design … Their lessons still apply …"), and every ledger has a `# Harvest:` heading.
- On the overlay I appended ` See testing/no-vacuous-pass.` to R0042's line 2 and added an indented sub-bullet `  - also testing/no-vacuous-pass`. Then:
  - the script made 211 rewrites and exited 0, and both lines kept `testing/no-vacuous-pass`;
  - `./zn lessons --check` said "34 lessons, 186 harvest entries, ok";
  - `lessons.spec` (AC5, whose real-tree case says "no harvest.md … names an old skill's id") reported 10 passed.
- AC4 doesn't see it either, because tracker documents are exempt. So AC5 passes a ledger that names an old id whose renamed lesson exists.

Critique: this is a hole in round 003's fix, not in its idea. Building the rule on the format's reader was right. But the rule splits a line into "parsed ids" and "a note's or one-off's prose", and leaves everything the reader never returns out of both. The tempting fix is another special case ("also scan heading and indented lines"). That patches one shape at a time again, the pattern rounds 001 to 003 kept finding.
Consequences: let the split be complete. The parsed id lists take the id rule. Every other byte of the file takes the prose rule: note text, one-off reasons, skipped lines and refused lines. The prose rule counts only a token whose renamed lesson exists, so `review/x` and `tracker/rafts/R0010` stay safe anywhere. A refused line still fails AC6, and it no longer needs its own "left alone" case. Unknown-id reporting (exit 1) stays limited to parsed ids.
Recommendation:
- In `ledgerLine`, a line `parseHarvest` returns no entry for takes `skills.oldLessonIds` / `renameLessonIds` over the whole line, refused or skipped alike. Reword §5's sentence to match ("every part of a ledger that isn't a parsed id list is prose").
- Add planted cases to `lessons.spec`:
  - a ledger whose heading or free prose line and indented sub-bullet name `testing/no-vacuous-pass` (renamed lesson present) is reported by `ledgerOldIds` and renamed by `renameLedger`;
  - the same lines naming `review/x` or `tracker/rafts/R0010` are left alone, byte-identical;
  - a refused line naming `testing/no-vacuous-pass` is renamed and still fails `--check`.
- Add mutant row M49: skipped lines left alone again (killed by the prose-line case).
- Rerun E4's overlay.

Lesson: zz-test/absence-scans-cover-every-form (a ledger is one of the live forms; every part of it must be covered), zz-arch/one-reader-per-format

### F2 [low] The stack moved past the measured base again: c0120 changed `fence.sh` and `repo-fence.spec` after bc550e9 ("c0120 final for its code review")
Where: Design intro; §11; Implementation step 1.
Evidence:
- `git log 685c627..impl-c0120` lists f74ebfc, 0e33cbb and e092c44 (review-003's lows), which change:
  - `z-nile/lib/fence.sh` (22 lines);
  - `tests/tooling/repo-fence.spec.luau` (+1);
  - `fence-inherited-env.spec`;
  - two testing lessons.
- `proto-c0120` is still bc550e9. c0115 edits comments in `fence.sh` and `repo-fence.spec` (§8).
- Their added lines name no skill, and the two lessons came in with this merge and are clean on the overlay (F1's run). So nothing breaks today, but "final" is no longer true.
Recommendation: drop "final" from the intro and §11, or say "bc550e9; c0120 changed `fence.sh` and `repo-fence.spec` after it (no skill text), rechecked at Implementation step 1". Step 1 already reruns §11, so no new work is needed in prep.

Verdict: changes
