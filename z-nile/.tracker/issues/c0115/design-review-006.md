# Review 006: c0115 (design mode)
Inputs: `prep-c0115` at 9154787; `design-review-005.md` and `design-refute-005.md`; the fix delta `e56a5e7..9154787` (`c0115.md`, `lessons.spec`, `rename-lesson-ids.luau`, `harvest.md`, `prototype.patch`); `z-nile/engine/lessons.luau` `ledgerLine` on `proto-c0115` at 0b9aae2; `./zn capture c0115` (fb7fd80, no marker); `./zn lessons --when design --full`. Narrow round (user-allowed past the cap): round 5's fixes, the overlay rerun, regressions. Everything ran in a scratch clone of the prototype (`c0115-review006/ov` in the scratchpad), never in the repository. The overlay: the prep tree's 34 lessons laid into their new folders, its five ledger folders (R0040, done/R0042, R0043, c0120 under `done/c0120`, c0115) copied in, a baseline commit.
Dropped from review-005: F1, F2 and F3 (fixed, checked below; one gap in F2's fix is F1 here).

Re-review of round 005:
- `prototype.patch` is byte-identical to `git diff -M bc550e9 0b9aae2`. `c0115.md`, `check.sh`, `acceptance/` and `experiments/` match the prototype's byte for byte.
- F1 (the one-off reason): fixed. `lessons.spec`'s every-part case is now one table with seven rows (id list, note text, one-off reason, heading, paragraph, sub-bullet, refused line). Each row is checked twice: found once and renamed in place with a count of 1, and the look-alike byte-identical with a count of 0. The `testing/never-a-lesson` one-off returns no unknown from either function.
  - M51 (a one-off line returned unchanged), spot-run: it fails the table case. Killed.
- F2 (separators): fixed in the code. `ledgerLine` now runs a `gsub` over `[^,]+` and keeps each chunk's spaces.
  - M52 (an untouched chunk trimmed), spot-run: it fails the separators case and the script-rename case. Killed.
  - One mutant of the same rule survives (F1 below).
- F3: fixed. E5 says "(M1 to M52)". The script's header and its comment in `fix` match §5.
- Overlay rerun on 0b9aae2:
  - 221 rewrites, exit 0, and a second run 0. 221 is round 5's 217 plus the four ids of c0115's three new harvest entries.
  - All five ledgers equal their old text with each `<old>/<slug>` mapped: a pure substitution.
  - The lesson-body changes are seven files and nine rewrites, read line by line. All are correct renames: "testing skill" → "zz-test skill", `ticket-prep` → `z-design`, "tracker skill" → "zz-rules skill", `architecture/guard-no-is-explicit` → `zz-arch/…`.
  - `./zn lessons --check`: "34 lessons, 193 harvest entries, ok". `--uncovered R0040 R0042 c0115 c0120 R0043`: covered. `./zn skills --check`: ok.
  - `./zn check c0115`: 12/13. AC12 is red for the right reason: R0034 is active and other branches change the skill folders.
- Regressions: none found. The delta touches only §5's ledger bullet, E4, E5, the Rules table (two new rows), the spec list and the Verification log.
- Scope (item 11): the capture has no marker and is unchanged. The title, Problem, Solution and Non-goals are untouched.
- Lessons (item 10): no lesson file changed this round. `harvest.md` gained three id-list entries and no notes, so there is nothing new to judge. The table answers zz-test/seed-every-enumerated-case for the parts of a ledger. It doesn't yet answer it for the positions of an id within a list (F1).
- Repository safety (item 9): no new command. The new cases are pure function calls on strings.

### F1 [low] No case puts spaces around a renamed id, so dropping them passes AC5 and rewrites every real multi-id ledger line
Where: `lessons.spec` "an id list keeps its separators and spaces byte for byte"; the Rules row "an id list is renamed in place, separators and spaces kept" (M52 only); `ledgerLine`'s `` return `{left}{new}{right}` ``.
Evidence:
- In the separators case, every renamed chunk is unspaced: `testing/no-vacuous-pass,` comes first after the head's `%s*`, and `,testing/no-vacuous-pass` comes last. The spaced chunks (` zz-test/a `, `zz-test/b  `) are never renamed.
- In the table's id-list row, the id is alone after the head.
- On the overlay, the mutant `return new` (also `{left}{new}` and `{new}{right}`) gives `lessons.spec` 12 passed, 0 failed. All of AC5 passes.
- The same mutant run on the overlay's ledgers turns `- design-review-001 F1: zz-test/absence-scans-cover-every-form, z-design/spec-design-correspondence` into `…-form,z-design/…`, and so every `a, b` line whose second id is renamed. `lessons --check` stays ok.
- Only a sed comparison outside the specs (E4's) sees it.

Critique: this is the canonical real form (`, ` with a renamed id in second place), and it's the one shape the case leaves out. The ledgers stay readable, which is why this is low, but the row claims a rule its case doesn't pin.
Consequences: none.
Recommendation:
- Add to the separators case a line `- design-review-001 F3: zz-test/a, testing/no-vacuous-pass ,zz-test/b` and expect `- design-review-001 F3: zz-test/a, zz-test/no-vacuous-pass ,zz-test/b`. That puts a renamed id with a space on each side.
- List the mutant "a renamed chunk's spaces dropped" as M53 against it.
- Rerun the runner for M51 to M53.
Lesson: zz-test/seed-every-enumerated-case

### F2 [low] Text to recheck when c0115 is rebased onto the upstream c0114 and c0120 changes (§11). Not judged here.
Where:
- §4 line 97 and G6 ("z-nile's home is `.`"), and `check.sh` line 5's comment ("cds to the item's project home: the root"). z-nile's home is now `z-nile/`.
- §4 line 146 ("The stage runs with or without `--project`"). The project is now chosen from the current directory.
- AC10's command (`lune run tests/run -- tests/tooling/…` from the root, then `cd pickman`), and `check.sh`'s `tests/acceptance/c0115` fallback. Both assume today's home layout.
- §5's "tracker documents, `check.sh` files among them, are history AC4 leaves out", and G4/§8's "c0120's check-paths spec keeps exempting them by content". Finished `check.sh` files are now rewritten, so they may no longer count as frozen history. c0115's own `check.sh` paths may be rewritten at `done`.

Recommendation: add these four places to §11's recheck list, so that Implementation step 1's rerun covers them.

Verdict: approve
