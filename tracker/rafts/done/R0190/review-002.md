# Review 002: R0190 (code mode)
Inputs: HEAD 9181d5b (diff `origin/main...HEAD`: `scripts/tracker/main.luau`, `scripts/tracker/store.luau`, `.claude/skills/tracker/SKILL.md`, c0500 Verification log); R0190.md, R0190 `check.sh`, c0500.md, c0500 `check.sh`, `acceptance/*.spec.luau`; review-001.md, refute-001.md.
Dropped from review-001: F1 (fixed in 9ca09c3 as recommended: one `originTree()` listing, each caller keeps its own fetch and failure behaviour).

Checks run by the reviewer:
- Sequestration: `git diff --find-renames=100% --name-status origin/main...HEAD -- 'tracker/**/check.sh' 'tracker/**/acceptance/**'` lists only `R100` moves to `active/`; `da73e0a..HEAD` touches no `check.sh` or acceptance file. Clean.
- `scripts/check.sh --full`: GATE PASSED (full), 925 passed / 0 failed over 138 spec files, wall time 56.5 s.
- `scripts/tracker.sh check c0500`: 3/3 (AC1 to AC3). `bash tracker/rafts/active/R0190/check.sh`: 4/4 (RC0, RC1).

The round-1 refactor:
- **`new` is unchanged.** On origin/main, `originIds(kind)` returns `{}` when publishing is off, otherwise runs `git fetch -q origin main` and then `git ls-tree -r --name-only --full-tree origin/main tracker/`, returning `idsOf(...)` or `{}` on failure. Now it makes the same publishing check and the same fetch, and `originTree()` runs the identical `ls-tree` argv, returning `{}` paths on failure, so `idsOf({}, kind)` is `{}`. The call sites (`new` issue at line 399, raft at 516) are untouched and still feed `store.nextNumber`, so the multiple-of-10 numbering, publishing and fetch are byte-for-byte the same behaviour. The c0510 specs and c0500 `new-spacing.spec` are green in the full gate.
- **`renumber` still matches the c0500 design**, apart from one recorded deviation. The design's adapter listed six directories with `ls-tree -d` and took basenames. The code reads the recursive full-tree listing through `idsOf` (`/<id>/<file>$`), and that deviation is recorded in the Verification log. Each design rule still holds:
  - Every item directory holds its `<ID>.md`, so every state on origin/main counts (rule 2). The `R`/issue predicate keeps the number spaces apart (rule 3).
  - Paths outside item directories are never mis-read as ids: on origin/main these are `architecture.md`, `game-design.md` and `templates/**`, plus nested `acceptance/` and `experiments/` files.
  - It doesn't fetch, and `ls-tree` failure stops with the designed message before anything moves (rule 4). `store.get(old)` fails first for an unknown id.
  - `--full-tree` makes the listing independent of the cwd, which the old six-path form wasn't.
  - The c0500 renumber spec cases that kill M5/M6/M13/M14 (state dirs, swallowed failure, HEAD, local main) all pass.

No findings.

## Judged criteria (code mode only)
None.

Verdict: approve
