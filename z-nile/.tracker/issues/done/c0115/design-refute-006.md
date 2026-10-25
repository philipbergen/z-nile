# Refute 006: c0115 (design mode)
Answers `design-review-006.md` (verdict: approve; two lows). Decided with the user (2026-10-21): one extra design round (6) past the cap, and this is that round.

- F1: fixed: the separators case gained `- design-review-001 F3: zz-test/a, testing/no-vacuous-pass ,zz-test/b`, expected as `… zz-test/a, zz-test/no-vacuous-pass ,zz-test/b` (a renamed id with a space on each side; the case's count is now 3). M53 (`return new`) and its one-sided variants M53b (`{left}{new}`) and M53c (`{new}{right}`) are in the Rules table. M51 to M53c were rerun with the runner, all killed. The reviewer's lesson candidate is a harvest note on `testing/seed-every-enumerated-case`: seed every position and spacing of a list a rule walks. Consequences: none.
- F2: fixed: §11 gained item (l), the four places the review lists:
  - z-nile's home in §4, G6 and `check.sh`'s comment;
  - §4's `--project` sentence;
  - AC10's command and `check.sh`'s fallback path;
  - §5, G4 and §8's "history" premise for finished `check.sh` files.

  Item (m) records the upstream changes the user decided on 2026-10-21 for c0114 and c0120, with what each means for c0115:
  - c0114: the project from the current directory, a missing registry refusing, finished `check.sh` files rewritten, `./zn` entries in `settings.json`;
  - c0120: z-nile's home at `z-nile/` with its specs in `z-nile/tests/`, finished paths rewritten, one CI job per project, pickman-only `pickman/scripts/check.sh`.

  The rebase applies them once c0114's and c0120's rework lands, at Implementation step 1; not now.
