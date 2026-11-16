# Refute 010: c0117 (design mode)

Verdict approve; both lows fixed. Reviewer spend: 35 minutes (recorded).

- F1: fixed: zz-review's Visible record reads "Write `review-NNN.md` in full (under `./zn dispatch`, `$ZN_DISPATCH_DIR/review.md`, as Output file says)", and the Output file's dispatched bullet says "The names above and in Visible record are the interactive path's"; docs.spec pins both (M175); consequences: none.
- F2: fixed: the failed-review rule ("A dispatched review that fails with \"the reviewer wrote no review\" still prints its `record:` line: commit that line alone …, then rerun the review, which is still the same round") moved to zz-execute Phase 4 step 3, which every raft reads; step 7 cites it ("handled as Phase 4 step 3 says"); docs.spec pins it inside step 3 and the citation (M176); consequences: none.
