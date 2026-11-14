---
title: After a rework, the old mutants are rewritten against the path the rule now takes
when: design
tags: [mutants, prototype, rework]
check: After a prototype round changes which function a rule goes through, is every earlier mutant of the old function still on the path the command calls? Is each mutant that now survives rewritten against the behaviour (the value the rule reads, its effect), not dropped as equivalent?
---
A mutant only tests a rule while it changes the code the command runs. When a rework moves a rule to a new function, the mutants of the old one keep applying cleanly. They now edit dead code and survive, and a survivor looks like a weak spec. A mutant that the code makes unreachable (a branch an earlier guard already returns from) is the same case.

**Why:** c0306 prep, round 3 (2026-11-14). When `reviewmodel.problem` moved from `files` to `newest`, M16–M18, M68, M69 and M85 survived because they still mutated `files`. M102 and M105 survived because `effortOption` already gave nil for a non-claude id, so their mutated branch was unreachable. All were rewritten, against `newest` and against the read of `CLAUDE_EFFORT`, and were then killed.

**How to apply:** after each round that moves code, grep the mutant definitions for the functions the round stopped calling, and rewrite those mutants on the new path. For a survivor, ask first whether the code can still reach the mutated line.
