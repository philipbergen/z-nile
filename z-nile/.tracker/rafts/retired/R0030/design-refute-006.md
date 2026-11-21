# Refute 006: R0030 (answers to design-review-006)

- F1: fixed. An item document is now a `.md` file in an item folder: the item's document, `spend.md`, reviews and refutes. Every other file in an item folder keeps the plain rule: its `check.sh`, every `*.spec.luau` (under `acceptance/` or elsewhere, such as c0053's `replacements/`) and its experiments. That is the user's option B read literally ("documents, `spend.md`, reviews"), without the earlier "everything except `check.sh` and `acceptance/`" boundary, and it answers the mechanism question with a positive list instead of exceptions.
  - The AC2 case now also checks that `tracker/issues/c9999/replacements/x.spec.luau` selects c0044's `guard` and c0006's `clone`.
  - The Design bullet, the Suites sentence (testing skill), AC2, the Rules rows and R0030's diagram and experiments line say the same.
  - Mutants run on the prototype and killed: "every file in an item folder is a document" and "only `check.sh` and `acceptance/` are exempt". They supersede option B's P2 and P3.
  - Consequences:
    - An item's experiments (`.luau`, `.py`, logs) now select by the plain rule, so a prep that adds experiments runs the `tracker`-token readers, which it already did for its new `check.sh` and specs.
    - A document's selection is unchanged.
    - The six-place loop (F2) still holds.
- F2: fixed. The AC2 case loops over a document in each of the six lifecycle places: `tracker/issues/c9999/c9999.md`, `tracker/issues/active/c9999/c9999.md`, `tracker/issues/done/c9999/c9999.md`, `tracker/rafts/R9999/spend.md`, `tracker/rafts/active/R9999/review-001.md` and `tracker/rafts/done/R9999/R9999.md`. It asserts that each one alone selects exactly `real-tree`.
  - Both of the review's mutants were run and fail that loop: "the rule skips the issue backlog and done rafts" and "the reader trigger fires only for `tracker/issues/`".
  - Option B's P1 and P4–P9 were re-run on the new rule and still fail.
  - Consequences: the case pins exact selections for synthetic ids (`c9999`, `R9999`). A real spec that one day names such a path would break it; ids that high are not in use, and the compaction keeps numbers low.

After the fixes the prototype passes c0083 9/9. The record (95 mutants) is in `tracker/issues/c0083/experiments/mutants.log`.
