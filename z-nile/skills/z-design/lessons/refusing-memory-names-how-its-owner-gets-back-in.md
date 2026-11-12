---
title: A refusal keyed on a per-checkout memory names how the legitimate owner gets back in, and what ends the memory
when: design
tags: [claims, memory, refusals, lifecycle]
check: For every flow in which one owner changes the claim's stamp itself (stop then ready, rafting to work, a completed claim, a reused worktree), what does the rule answer in the checkout that remembers the old stamp, which act only the owner makes lets it in, and which command ends the memory (does that command run in the checkouts that hold it)?
---
A rule that refuses when the remembered stamp differs from origin's cannot tell the owner's own re-claim from a takeover, because the commands are the same. Without a stated way back in, the owner's documented flow is refused for good.

**Why:** c0274 design review 001 F1 and F6: the owner's `stop` then `ready` (z-stop step 4's keep path) left its worktree refused by `--adopt` and `done`; the Design said `stop` ended the memory, but `stop` only runs in the main checkout, which holds none; and a rafting memory (`preparing-…`) read as taken once the raft was readied (`active-…`).

**How to apply:** first look for a fact the engine can read that tells the owner's act from a taker's (here: the verdict at the moment the stamp changed, recorded by the command that changed it), and fail closed on it. A flag "never told" to the old process is no guarantee once the rules skill, the usage line and the exhaustive lists must name it (c0274 design review 002 F1). Also say which command in which checkout ends each memory, and remove every file the reader falls back to. The fact must tie the remembered stamp to the current one, not only say how the remembered claim ended: between the two, could another claim have started and ended, and does the rule read that chain? (c0274 design review 003 F1.) Bind two records of a chain by the value one wrote and the next replaced, never by "the latest record of type X before Y", and list every command that can change the item's state between them (c0274 design review 004 F1). When the fourth attempt at a mechanism still leaks, drop the mechanism (c0274: "Drop in-place re-adoption").
