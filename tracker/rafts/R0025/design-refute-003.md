# Refute 003: R0025 design review 003

- F1: fixed: c0067's AC11 greps only the five done checks prep edited (c0005, c0045, c0046, c0047, c0053), so c0067's and R0025's own `check.sh`, which name make-prompt, can't turn it red after the merge. The AC11 text was updated to match. consequences: none.
- F2: fixed: c0008 AC3's phrases (the tracker skill's done row and Merging step 3, and execute-raft Phase 5) were added to c0067's Regression guard, and RC5 now also runs c0008's done `check.sh`.
- F3: fixed:
  - c0067 gives the exact refusal texts: `the main checkout is on <branch>, not main` and `the main checkout is not clean: …`;
  - c0070 describes the real order: the refresh in `published()` runs before the command's own pull, and its sweep does the work;
  - c0067 drops "to the clipboard" from the interim USAGE `prompt` line, because AC10 bans the word.
