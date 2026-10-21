# Refute 002: c0115 (design mode)
Answers `design-review-002.md`. The prototype `proto-c0115` was rebased onto `proto-c0120` b7e75b9 first (c0120's code-review fixes, stable per the coordinator): the simulation commit, then the move (31 `R100`) and the edits cherry-picked, clean.

- F1: fixed: there is now one rule, in `z-nile/engine/skills.luau`, and the rename script, AC4 (`absence.spec`) and AC5 (`lessons.spec`) all call it (§5):
  - `skills.oldLessonIds(text, existing, ledger)`: every token in a ledger, and in prose only a token whose renamed lesson exists, never after a name character, `/` or `.`;
  - `skills.renameLessonIds` (the script's rename);
  - `skills.lessonIndex` (the existing lessons);
  - `skills.oldNames` and `skills.renameOldNames` (the name forms, which `absence.spec`'s scan now calls too).

  The map lives between `-- c0115 rename map: begin/end`, the one block AC4 leaves out.

  `lessons.spec` gained the reviewer's planted cases:
  - a ledger counts `testing/unknown-slug`;
  - a lesson body with `` `tracker/next` ``, `scripts/tracker/x`, `testing/unknown-slug` and `z-nile/.tracker` passes, and `testing/no-vacuous-pass` fails;
  - `renameLessonIds` renames the known id and reports the unknown one.

  `absence.spec` gained a rename case for the name forms. Mutant M46 (the prose rule widened to every token): run, killed.

  Consequences: the rerun the reviewer asked for, AC3 to AC6 on the merged prep tree's lessons and ledgers laid over the prototype (E4), first failed AC4. Five prep-tree lessons named `ticket-prep` and "testing skill" in prose: the prototype's lessons had been renamed by the prep's own helper, which doesn't ship, and the shipped script renamed ids only. The script now also renames old skill names in lesson bodies with `skills.renameOldNames`, the rule AC4 checks with. On the overlay it made 204 rewrites with exit 0, a second run 0, and AC3 to AC6 pass there (34 lessons, 179 entries). M47 (a promoted spec's file name counted as an old skill): run, killed.
- F2: fixed: AC2 is `links_check` in `check.sh`:
  - it makes a plain `git clone -q --no-hardlinks` of HEAD into `.cache/c0115-ac2`, never `git worktree add`;
  - in the clone, `./zn skills --check` must print its "one link each, ok" line, and `z-nile/check.sh --plan` its `skills:` line;
  - the clone's `git status --porcelain` must stay empty;
  - it removes the clone, then greps the stage line in the real `z-nile/check.sh`, which only reads.

  §4 and AC2's text say so. M37 against AC2, committed on a scratch branch since the clone reads HEAD: killed (the write mode prints "skills: 12 skills linked", not the ok line). Consequences: AC2 now checks the committed links, as CI does, so uncommitted links fail it: intended.
- F3: fixed:
  - Rebased onto b7e75b9. Its one testing-skill line (Overrides stripped) is in `zz-test`.
  - R0043's later Writers, Gate spec and Hooks bullets are now `zz-test`'s, taken from `impl-c0120`'s testing skill and renamed. The c0114, c0120, c0111, c0081 and c0077 docs specs pass with them.
  - §11 now names the whole stack (R0043, then c0120): (a) covers every line the stack changes, and the new (k) covers R0043's later edits elsewhere, checked by E4's overlay and by `skilldiff.py`, the prep's line-by-line comparison of the prep tree's renamed skills with the prototype's.
  - Counts: five architecture lessons on the prep tree; E4's numbers; the log's 34/179 (this round's harvest adds four entries and one lesson to the reviewer's 33/175).
- F4: fixed: the lesson `absence-scans-cover-every-form` now names the old ids in words ("the old testing-skill id of the no-vacuous-pass lesson"), and §5's "Text" bullet states that rule for any lesson quoting an old id as history.

Lesson: the reviewer's candidate is `testing/one-rule-one-function`, harvested with F1.
