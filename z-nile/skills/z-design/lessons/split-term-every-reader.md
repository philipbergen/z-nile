---
title: A term that changes meaning is re-read by every rule that uses it
when: design
tags: [restated-rules, review-rounds]
check: After the edit, does every sentence that uses the changed term ("the final round") pick out the same thing in a walk where the new case happens (an expensive round that holds a high, a cheap round that would have stopped), and is the old definition deleted, not kept beside the new one?
---
When a design adds a case to a defined term (a "final round" that can now be a cheap round or an expensive one), the rules that read the term (the ready rule, the escalation rule, the merge block, `done`'s "latest review round") each silently pick one meaning, and keeping both definitions in one bullet lets a doc spec that pins only the new sentence stay green.

**Why:** c0261 design review 002 F2: the prototype kept "the final round is the round after which the rule runs no further round: any round 1 to 4 where it says stop" beside the new "the next round is run with `--final`"; read the old way no expensive round ever ran, read the new way a `--final` round 2 with a high escalated early.

**How to apply:** keep the term for one thing, state the invariant that makes the new case safe (the last round is always a `--final` round), rename the new case with the words already in use, delete the old sentence, and add an absence case for it.
