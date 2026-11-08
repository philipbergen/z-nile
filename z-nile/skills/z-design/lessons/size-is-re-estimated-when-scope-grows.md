---
title: Re-estimate size when scope grows; split before review, not after
when: design
tags: [size, scope, process]
check: Was the issue's `size:` re-estimated from the real design (or from a prototype's diff) each time its scope, design or specs grew, and if it is over the raft cap of about 1,500 changed lines, or its specs have tripled since the first estimate, did a split go to the user before the first review round?
---
`size:` is z-raft's input: it sums the sizes against its cap of about 1,500 lines. An estimate written in round 1 and never touched again lies once the design grows, and an issue that has outgrown the cap is cheaper to split before review than after it.

**Why:** c0265 (z-nile) carried `size: 640` from round 1 to round 18 while its Design grew from one storage choice to six interlocking mechanisms (lease, verdicts, automatic beats, ownership memory, board verdicts, discarded worktrees) and its specs tripled to about 2,300 lines. Every fix in one mechanism opened an edge in another, and 18 rounds (3.5 M tokens) did not converge. The user split it into five issues in one raft, delivered a layer at a time (2026-11-08).

**How to apply:** after every round that adds a mechanism, a command or a spec file, re-estimate `size:` from the diff of the prototype (code, skills and docs, not prep's specs) and write it down. Watch the other symptoms: specs growing faster than code, a fix that needs a new Rules row in an unrelated mechanism, a third review round that is still major. When the design has more than about three interlocking mechanisms, or the estimate passes the raft cap, stop and put the split to the user with the cost of each option (z-design: a split is the user's call and records a `Scope decision` line), before another review round is paid for.
