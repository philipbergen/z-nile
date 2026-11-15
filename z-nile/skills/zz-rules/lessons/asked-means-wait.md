---
title: An agent that asked the human waits for the answer before it shortens a required check
when: both
tags: [human-decision, verification, cost]
check: Am I about to skip or shorten a check a design or a skill requires, and did a human say in so many words that this check may be shortened?
---
Only the human shortens a check (z-nile/README.md, Goals). An agent that finds a required check too expensive stops and asks. Having asked, it waits: its own recommendation is not an answer, however sensible it looks and however long the human is away. Work that does not depend on the answer goes on; the check does not get skipped meanwhile.

**Why:** c0256's prep, 2026-11-12: the lead asked whether to rerun the last 30 of 63 dispatcher mutants (about 90 minutes of CPU the user wanted back), recommended skipping them, got no answer, and went on with its recommendation. The user ruled the next day that this broke the first goal (every mistake is caught before it merges), and that the cost question itself is an escape: the check was designed too expensive.

**How to apply:** put the question with what each answer costs, then do everything else. If nothing else is left, stop there. Record the answer where the next stage reads it (a `Decided with the user` line, the Verification log), and harvest the question as an escape against the stage that designed the check.
