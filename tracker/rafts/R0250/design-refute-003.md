# Refute 003: R0250 design review 003

- F1: fixed: c0730's AC11 greps only the five done checks prep edited (c0041, c0430, c0440, c0450, c0510), so c0730's and R0250's own `check.sh`, which name make-prompt, can't turn it red after the merge. The AC11 text was updated to match. consequences: none.
- F2: fixed: c0070 AC3's phrases (the tracker skill's done row and Merging step 3, and execute-raft Phase 5) were added to c0730's Regression guard, and RC5 now also runs c0070's done `check.sh`.
- F3: fixed:
  - c0730 gives the exact refusal texts: `the main checkout is on <branch>, not main` and `the main checkout is not clean: …`;
  - c0760 describes the real order: the refresh in `published()` runs before the command's own pull, and its sweep does the work;
  - c0730 drops "to the clipboard" from the interim USAGE `prompt` line, because AC10 bans the word.
