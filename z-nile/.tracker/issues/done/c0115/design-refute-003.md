# Refute 003: c0115 (design mode)
Answers `design-review-003.md`. The prototype `proto-c0115` was first rebased onto `proto-c0120` bc550e9 (c0120 final for its code review): the simulation commit, then the move (31 `R100`) and the edits cherry-picked, clean.

- F1: fixed: the pattern was not narrowed again. The ledger rule now reads each line through the format's own reader:
  - `lessons.ledgerOldIds(text, existing)` and `lessons.renameLedger(text, existing)`, in `z-nile/engine/lessons.luau` beside `parseHarvest`, read each `harvest.md` line through `parseHarvest`;
  - every parsed id of an old skill counts, known or not, and is renamed in the id list;
  - a note's text and a one-off's reason take the prose rule `skills.oldLessonIds(text, existing)`, which lost its ledger flag: it counts a token only where the renamed lesson exists;
  - a line `parseHarvest` refuses is left alone, since `lessons --check` (AC6) fails on it already.

  The rename script (`renameLedger`), AC5 (`ledgerOldIds` in `lessons.spec`'s real-tree case) and AC4 (the prose rule) call these. `lessons.spec` gained the planted cases asked for:
  - a note naming `review/x` and `tracker/rafts/R0010` beside a valid id passes, and so does a one-off reason naming `testing/fixtures` and `review/round`;
  - an entry listing `testing/gone` is reported unknown;
  - `testing/no-vacuous-pass` in a note's id list counts;
  - the script's ledger rename renames ids by the list and prose by the prose rule, leaves `review/x` alone, and leaves a clean ledger byte-identical.

  Mutant M48 (a ledger line's every token taken as an id again): run, killed. M46 was retargeted to the prose rule and is killed.
  Consequences: `skills.luau` can't call `parseHarvest` (`lessons.luau` already requires `skills.luau`), so the ledger rule lives in `lessons.luau`, the format's owner (lesson zz-arch/one-reader-per-format); §5 says so. I reran the overlay with the reviewer's probe (a note naming `review/x` and `tracker/rafts/R0010`): 203 rewrites, no unknown id, a second run 0, and AC3 to AC5 pass. The lesson `one-rule-one-function` got a sharper check: where the rule reads a format, is it built on that format's reader?
- F2: fixed:
  - `plain-find-for-literals` now shows `string.find(s, "ab-cd")`, which gives nil in Lune, as the old example did. I checked first: `"a-b.c"` matches at 3..5, so it wouldn't have shown the point.
  - `instructions-runnable-where-they-run` says "a prep author reads the design skill and the testing skill"; after the rename, "the design skill and the zz-test skill". Both edited in prep at the old paths and in the prototype.
  - §5's Text rule now covers old names as well as old ids.
  - Implementation step 5 says to read the script's lesson-body diff line by line after every run. This round's eight changes were read and all are correct renames.
- F3: fixed: rebased onto bc550e9 under §11:
  - its diff since b7e75b9 is `fence.sh` and two tooling specs, with no skill text;
  - (a) to (k) rechecked; the prep tree's testing-skill lines that are missing from `zz-test` are now only the pre-c0120 lines c0120 rewrote;
  - the full gate, `check.sh`, the dry run and every mutant were rerun.

  The intro names the base by sha, and `prototype.patch` is `git diff -M bc550e9`.
