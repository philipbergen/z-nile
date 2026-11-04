---
title: A rafted member's fix takes two landings: unfold with the edit, then fold again
when: design
tags: [raft, claim, re-prep]
check: When a member of a backlog raft needs a design change, is it unfolded with the edit and its approving round in one landing, then folded again in a second landing (the raft's `grouped:` is recorded from origin/main), with the coherence review rerun if the raft has several members?
---
`./zn status <id> preparing` refuses an issue that is in a raft on origin/main, and `./zn unfold` changes only the branch, so unfold-then-claim needs a landed PR in between. `./zn status <R-id> preparing` claims the raft on origin/main but does not record the claim in the checkout, so `unfold` and `release` then refuse it as someone else's.

**Why:** f0126 (R0053), 2026-10-26: f0109's prep changed its colours after f0126 was rafted; claiming R0053 with `status` left no claim file, unfold refused, and the claim had to be recorded by hand in `.cache/tracker-claim-R0053`.

**How to apply:** a change to a rafted member's design takes two landings, because `grouped:` is recorded from origin/main and `fold` refuses a member whose `raft:` on origin/main still names a raft. (1) In a rafting worktree `./zn unfold <R-id> <id>`, make the edit, add the member's approving design round (`./zn design-record <id>` quote, once c0161 lands), `./zn status <R-id> prepared`, and land. (2) In a second rafting worktree `./zn fold <R-id> <id>`, the coherence review if the raft has several members, `./zn status <R-id> prepared`, and land. The cost is one extra PR per in-raft member fix. A plain re-fold in the same PR is refused ("already belongs"), and a landed raft whose member was edited in it is refused by `./zn ready` ("changed on origin/main since … grouped it"). A chore that edits another prepared issue's design files runs the round for the edited issue in its own worktree.

f0126 design review 013: the re-fold was kept for the very end of the branch, after round 3's answers.
