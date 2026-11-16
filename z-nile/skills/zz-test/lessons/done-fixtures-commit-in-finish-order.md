---
title: A fixture that drives done commits in the order finish allows
when: both
tags: [fixtures, done, finish, trace]
check: Does a fixture that ends in `./zn done` commit every stream review and every file outside the raft folder before `./zn finish`, commit after `finish` only what `layergit.isPostFinishPath` allows (the raft folder's `review-`, `refute-`, `final-review-`, `final-refute-` files, `trace.md`, the raft document and `spend.d/`), and write the trace last?
---
After a layer is finished, a later commit may touch only the post-finish paths `layergit.isPostFinishPath` names. Those are the raft folder's review, refute and final files, `trace.md`, the raft's own document, and `spend.d/`. Anything else makes the layer unfinished again. Any commit after `seal.trace` stales `trace.md`, whose record names the top commit, so `done` refuses the trace.

**Why:** c0306 prep (2026-11-14). The prototype's `done.spec` fixtures judge stream reviews and a review in a member's folder. They passed only once those were committed before `./zn finish` and the trace was written last (reported by the prototype's author). In any other order, `done` refuses for the order, not for the review-model rule the cases pin.

**How to apply:** in a fixture, write and commit the layer's work, any stream review and any review in a member's folder, then `./zn finish`. Then commit only raft-folder reviews and refutes. Then call `seal.trace` as the last commit before `./zn done`. A case that pins a refusal of `done` must also show `done` passing on the same fixture with the one fact changed, so the refusal is the rule's and not the order's.

**Note (c0306's prep, round 3, 2026-11-14):** this also holds for a case that follows a refusal of `done` to a pass. `./zn commit` after `./zn finish` rewrites the raft's `spend.md`, which `layergit.isPostFinishPath` does not allow, so the layer reads as not finished. That case commits the new round, runs `./zn finish` again, then `seal.trace`.

**Note** (R0109 final review 001 F4): the protocol now commits `trace.md` twice, the skeleton and then the filled table. `staleReason` judges from the last commit that touches the file, so an issue document between the two is current once the filled table is committed, a source file between them is still "after finish", and an issue document after the filled table is "after trace.md". Anchoring on the first such commit turns the filled table, which touches `trace.md` and which `isAllowedAfterTrace` does not name, into "after trace.md". Pin both, so the anchor is a decision. d0333 lets the raft's own `spend.md` through the same lists.
