# Refute 004: c0115 (design mode)
Answers `design-review-004.md`. The base is unchanged: `proto-c0120` bc550e9.

- F1: fixed: every byte of a ledger now takes one of two rules. `lessons.luau`'s `ledgerLine`, which `lessons.ledgerOldIds` and `lessons.renameLedger` (the script, AC5) share, works like this:
  - the id list of an entry `parseHarvest` returns takes the id rule (every old id counts, known or not, and is renamed in the list);
  - the rest of that line takes the prose rule (`skills.oldLessonIds`, the one AC4 uses): its review and finding, a note's text, a one-off's reason;
  - so does every line `parseHarvest` skips (headings, paragraphs, indented sub-bullets, blank or odd lines) or refuses. A refused line still fails `lessons --check` (AC6) after it is renamed;
  - unknown-id reporting (the script's exit 1) stays limited to parsed ids.

  §5's premise is reworded ("Every other part of a ledger is prose").

  `lessons.spec` gained the every-byte case:
  - your two repros (a heading, R0042's paragraph shape and an indented sub-bullet naming `testing/no-vacuous-pass`) are found by `ledgerOldIds` and renamed by `renameLedger`;
  - the same shapes naming `review/x`, `tracker/rafts/R0010` and `testing/fixtures` stay byte for byte;
  - a refused line is renamed and still fails `parseHarvest`.

  M49 (skipped lines left alone again) and M50 (an entry's own prose not scanned): run, killed. With M46 and M48 all four ledger mutants are killed.

  The sweep for other readers that skip lines found none:
  - AC4 reads every live file whole (SKILL.md, lesson frontmatter and body, the README, code, every `.md`) through `skills.oldNames` and the prose id rule;
  - AC5 and the script read lesson files whole;
  - `parseHarvest` is the only line-based reader any of c0115's rules goes through;
  - tracker documents, `check.sh` files among them, are history that AC4 leaves out by design (§8).

  The overlay ran again with your probes plus a note and a paragraph naming `review/x` and `tracker/rafts/R0010`: 213 rewrites (211 plus the two probes), exit 0, a second run 0. Both probes were renamed and the look-alikes untouched; `lessons --check` ok; AC3 to AC5 pass.
  Consequences: none beyond the rule itself; refused lines now get renamed as well, and they still fail AC6.
- F2: fixed: the intro and §11 no longer call bc550e9 "final". They name it as the measured base, and say that `impl-c0120` changed `fence.sh`, `repo-fence.spec`, `fence-inherited-env.spec` and two testing lessons after it (no skill text), and that Implementation step 1 reruns §11 against c0120's landed tree.
- The coordinator's item (the type error at `lessons.spec.luau` line 215): fixed in the prototype and in prep. The new every-byte case passed `string.find`'s two results to `t.expect`, and the call is now wrapped in parentheses. Why it reached a commit another agent read: my promotion dry run did catch it (`luau-lsp analyze tests` exit 1, in the run right after the gate). But I had already amended the edits commit before that run, so the shared branch carried the unwrapped line, as 8c917d7, until the fix was amended in. The dry run worked; the order was wrong. I committed before running the one check the spec runner skips (lesson ticket-prep/rerun-skipped-checks-after-edits). From now on the type check runs before a commit to the prototype branch. After the fix: `luau-lsp analyze tests` with the specs promoted exits 0, the seven specs pass (55 cases), and the full gate passes.

Lessons: the reviewer's candidate is a note on `testing/one-rule-one-function` (a rule built on a reader covers the lines the reader skips). The commit-before-type-check slip is a note on `ticket-prep/rerun-skipped-checks-after-edits`.
