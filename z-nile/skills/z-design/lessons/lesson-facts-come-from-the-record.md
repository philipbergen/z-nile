---
title: A lesson's incident and examples come from the landed record and the tool's code
when: design
tags: [lessons, evidence, history]
check: For each quote, owner and tool rule a lesson chore's text states (its Why, its How to apply, its examples), does it match, word for word, the final landed record it cites (not an intermediate round's fix) or the code that enforces the rule, and does a check read each quote from the lesson itself and find it in that record?
---
A lesson chore's Why is written from the capture's one-line summary, which paraphrases. The paraphrase then reads as a quote, an owner settled in an early round reads as the outcome, and an example states a tool rule from memory. A check that greps a short substring of its own choosing passes all three.

**Why:** c0294 design review 001 F1 and F5 (2026-11-15): the Why quoted c0257 in words c0257 never had, said "c0249 took that part too" (round 1's fix, which F26 in round 2 overturned: lost work first stayed c0290's), and the how-to said `./zn land` cannot edit a ticket being prepared, while land's rule (`main.luau`) is `design: draft` on both sides; AC4 checked only `by the order c0249 defines`.

**How to apply:** read the cited record at its final commit (`git show <sha>:<path>`) and the rule's code before writing; quote it exactly; and have the check extract each quote from the lesson and require it, fixed-string, in that record.
