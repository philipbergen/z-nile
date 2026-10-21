# Refute 001: c0115 (design mode)
Answers `design-review-001.md`. The prototype `proto-c0115` was rebased onto `proto-c0120` d6e36fa first (F4): the simulation commit again, then the move (31 `R100`) and the edits cherry-picked, both clean.

- F1: fixed: `absence.spec` gained the lesson-id scan, using the rename script's own rule. It collects every existing `<new>/<slug>` from both skills folders, and flags `<old>/<slug>` in any live file (skills, lesson bodies, `.md` and code) only where the mapped lesson exists and the token doesn't follow `/` or `.`. Its planted-text case catches `architecture/guards-trust-only-origin` and `testing/no-vacuous-pass`, and leaves `tracker/next`, `tracker/compaction.txt`, `scripts/tracker/x.luau` and an unknown slug alone. §8 and AC4 say so. Mutants M41 (zz-test keeps `testing/no-vacuous-pass`) and M42 (the reviewer's `publish.luau` probe): run, killed. Consequences: the rename script had the same look-alike problem in reverse. Run on a copy of the prep tree, it reported `tracker/next` from a lesson body as a missing id and exited 1. It now reports a missing id only in a `harvest.md`, where every token is an id. The prep-tree run then rewrote 185 ids with exit 0, and a second run rewrote 0 (E4).
- F2: fixed: `skills.linkedParents(root)` readlinks `.claude` and `.claude/skills`. With either one a link:
  - the write mode refuses before `apply`, and `apply` refuses again by itself, so nothing is written;
  - `--check` reports the link in place of the `diff` problems, which would otherwise be read from the link's target.

  `trackedNonLinks` now also reports `.claude` or `.claude/skills` tracked itself, in any mode, and a link deeper than `.claude/skills/<name>`. `skills.spec` gained three cases:
  - a `.claude/skills` linked to a sibling folder under the fixture holding a stray link: `skills` and `--check` both refuse, the stray link survives, and nothing is written there;
  - a committed `.claude/skills` link fails `--check` ("tracked itself");
  - a linked `.claude` is refused.

  Mutants M35 and M36: run, killed. The deeper-link report is a `reasoned` row: a working tree can't hold one.
  Consequences: a tree with no `.claude/skills` yet still works (readlink of a missing path is no link; the fixture's first run creates it).
- F3: fixed: Implementation steps 1, 9 and 10 run `./zn sync --fetch` before `busy` and `check.sh`; §9 says `busy` reads the last fetch; AC12's text and its `check.sh` label say "as of the last fetch". Consequences: none (c0120's rule).
- F4: fixed: rebased onto d6e36fa, and the new §11 "Rebase on c0120" lists (a) to (j) as a rule for any later rebase, also at Implementation step 1. Rechecked on d6e36fa:
  - (a) c0120's new Protected-writers and Fence lines are in `zz-test`;
  - (b) and (c) the c0120/docs and c0120/homes overrides pass, and c0120's new spec edits name no old skill;
  - (d) `engine.REGISTRY` keeps pickman at `tracker`;
  - (e) c0120's specs promote to the root;
  - (f) `pickman/tests/meta/fence.spec.luau` exists, and check-paths passes with c0115's Touched modules;
  - (g) AC2 passes;
  - (h) `busy` is unchanged (reads origin, skips the current branch);
  - (i) `projects.parse`, `legacy`, `projectOf` and `load` are there;
  - (j) c0120 didn't touch the tracker skill since 080d247.

  M1 to M45 and the full gate were rerun, and the patch regenerated. Consequences: the list itself must stay current, so §11 says a later design round adds to it in the same change. The prep tree is also ahead of the prototype on lessons (R0043's seven, its ledger, c0120's ledger), so E4 now also runs the rename script on a copy of the prep tree.
- F5: fixed: `prototype.patch` sits in this item's folder; the intro says "three kinds of commit"; §1's checklists reference is §7.
- F6: fixed: rows for "`--check` writes nothing" (M37), "a plan problem writes nothing" (M38) and "a second run changes nothing" (M39); a `lessons.spec` case for "`<id>: no skill <s> (no <s>/SKILL.md in any skills folder)`" with its row (M40). All run, killed.
- F7: fixed: `readme.spec` now walks every `z-`/`zz-` token in the whole block, in any node shape. Each must sit inside a quoted label on its line, and that label alone must carry `(<issue>, planned)` when the skill has no folder. M43 (an unquoted `ghost[zz-ghost]` node): run, killed.
- F8: fixed: §10 names the override c0116, c0117 and c0118 each inherit: `tests/acceptance/c0115/readme.spec.luau`, on their `Overrides:` lines, with `z-nile/README.md` and `tests/acceptance/c0115` in their Touched modules. `layout.spec` needs nothing for `z-raft`.
- F9: fixed: AC13 is a `check.sh` function (`moves_only`) over `merge-base origin/main HEAD..HEAD`. It asserts exactly one commit whose subject starts `c0115: move the skills`, all `R100` under `--find-renames=100%`, and no other commit of the range renaming a file under the three skill paths. It is a branch check, like c0114's AC13, so after the squash merge the range is empty (G11). JC1 keeps only the reading judgment. M44 (an edit amended into the moves commit) and M45 (a later commit renaming a skill file): run in a scratch clone, both killed.

Lessons: the reviewer's candidate is `testing/absence-scans-cover-every-form`. The prep's own two are `testing/promoted-specs-pin-rules-not-sets` and `ticket-prep/bulk-renames-skip-ordinary-words`, harvested as notes in `harvest.md`.
