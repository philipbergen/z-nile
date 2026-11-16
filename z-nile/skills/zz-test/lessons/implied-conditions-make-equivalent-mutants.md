---
title: Dropping an implied condition is not a mutant
when: design
tags: [mutants, specs]
check: For a mutant that drops one condition of a test, does another condition the code also checks already imply it (a claim stamp and a folder), so that the mutant is equivalent and the row needs both dropped, or a different mutant?
---
When two conditions guard the same outcome and one implies the other, dropping the weaker one changes nothing. The mutant survives for the wrong reason, and the spec looks weaker than it is.

**Why:** c0250's prototype: "a done member moved back with the raft" survived until the claim-stamp condition was dropped too, since a member in `done/` never carries the raft's `active-` stamp.

**How to apply:** before recording a survivor, check whether the code holds an implied guard; mutate the pair, or name the mutant equivalent in Unknowns with the reason.

**Note (c0306's prep, 2026-11-14):** the same holds across two layers that filter one input. M16 ("the code kind also takes stream reviews") survived because `reviewfiles.read`, the folder reader, already drops stream files before `reviewmodel.files` sees them. The mutant had to edit both filters. Mutate the first place the unwanted input is dropped, or every place.

**Note** (c0249 prep, 2026-11-16): an equivalent mutant can show that the clause it removes is dead code. c0249's `rank.next` checked `blocked` although a blocked item's status already excluded it. Remove the redundant clause and aim the mutant at the condition that really decides (the status test), rather than keeping code no case can see.
