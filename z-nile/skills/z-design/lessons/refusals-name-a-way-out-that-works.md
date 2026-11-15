---
title: A refusal names a way out that works under the rules that already hold
when: design
tags: [refusals, usability, specs]
check: For each refusal the design adds, followed literally (the command it prints, and the subagent route) under every rule that already holds (one round per kind, a record written once, a file never edited after it is written), does the refused item reach a pass for each caller of the refusal, and does a case prove it by doing only what the refusal says?
---
A refusal is only as good as its way out. When the way out it names is itself refused by an existing rule, the item is stuck for good. The refusal's text then sends the reader into a loop that no case notices, because specs tend to clear a refusal by rewriting the fixture in place, not by doing what the refusal says.

**Why:** c0306 design review 001 F2 (2026-11-14). A marked item whose review was recorded off the review models was told to "run the round again". But each review kind gets one round (the dispatcher and zz-review refuse a second), a record is written once, and every round was judged, so the old round still failed. The specs cleared each refusal by rewriting the review file, which the protocol forbids. The user ruled that a later round on a review model supersedes a refused one.

**How to apply:** for each refusal, list the rules its way out must pass, and follow it to a pass in a spec using only the commands the refusal names. If an existing rule blocks every way out, the exception it needs is a decision for the user, made at prep.

**Note (c0306's prep, round 4, 2026-11-14):** follow the way out once for each caller of the refusal, since callers can differ. `ready`'s "make it in a worktree, land it by pull request" was right for a raft's own coherence review. For a grouped member's design review it was wrong: a new round changes the member's design record, and `ready` then refuses it as "changed since grouped". The member's route is unfold, redo the round in its prep, and fold it back.
