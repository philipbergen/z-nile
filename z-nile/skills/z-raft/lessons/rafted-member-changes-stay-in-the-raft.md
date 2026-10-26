---
title: A rafted member's fix is made in the raft and folded again
when: design
tags: [raft, claim, re-prep]
check: When a member of a backlog raft needs a design change, is the raft claimed with a command that remembers the claim (`fold`, not `./zn status <R-id> preparing`), and is the member folded again after the change so the raft's `grouped:` record covers the new design? Is the member folded again only after the final round's answers, so `grouped:` hashes the approved text?
---
`./zn status <id> preparing` refuses an issue that is in a raft on origin/main, and `./zn unfold` changes only the branch, so unfold-then-claim needs a landed PR in between. `./zn status <R-id> preparing` claims the raft on origin/main but does not record the claim in the checkout, so `unfold` and `release` then refuse it as someone else's.

**Why:** f0126 (R0053), 2026-10-26: f0109's prep changed its colours after f0126 was rafted; claiming R0053 with `status` left no claim file, unfold refused, and the claim had to be recorded by hand in `.cache/tracker-claim-R0053`.

**How to apply:** claim the raft with `./zn fold <R-id> <member>` (it remembers the claim and records the member's design anew); make the member's change in the same branch; fold it again at the end so `grouped:` matches; then `./zn status <R-id> prepared`. A tool fix (status remembering raft claims) is worth an issue.

f0126 design review 013: the re-fold was kept for the very end of the branch, after round 3's answers.
