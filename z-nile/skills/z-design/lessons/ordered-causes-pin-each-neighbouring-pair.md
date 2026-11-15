---
title: A rule that names the first of several causes pins their order
when: design
tags: [specs, mutants, rules]
check: When a rule names the first cause found in a fixed order, does a spec case combine each pair of neighbouring causes, so a mutant that swaps two of them fails?
---
A refusal or skip that reports "the first cause found, in this order" has an order that is itself a rule, and a separate case per cause does not pin it: every case holds one cause, so any order passes. A mutant that checks a later cause first survives, and it prints the wrong instruction: a wait that never ends, where the earlier cause would have named who decides.

**Why:** c0286 design review 001 F5: the tie verdict lists eight causes in order, and each case had exactly one. The mutant "check waiting members before the raft's state" passed all thirteen cases, and on a tie whose raft was readied while a member was still new it would print "not prepared yet: raft-plan rafts them together when every one is", which never comes true.

**How to apply:** for each neighbouring pair (1 and 2, 2 and 3, …) write one case whose input has both causes and expects the earlier one, and run the swap as a mutant in the Rules and mutants table. Pairs that can't co-occur say so in the Design.
