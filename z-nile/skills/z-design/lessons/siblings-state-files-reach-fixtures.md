---
title: A sibling layer's state file reaches this layer's fixtures through the copy of the tooling
when: design
tags: [fixtures, layers, state]
check: Which files does the fixture copy (`engine.copy`, `engine.PATHSPECS`, a harness's seed commit) take from the working tree that a sibling layer of the same raft adds, and do this layer's specs pass on a tree where that sibling's last step has run?
---
A layer's specs run on the raft's final tree, where every sibling's files exist, and a fixture that copies `z-nile/<name>` brings them along. A claim that "the sibling's rule is not in force in our fixtures" is a claim about files, and it holds only until the sibling's file is committed.

**Why:** c0282 design review 001 F1: the design said its specs "seed no frozen list, so c0283's doors are not in force". `engine.copy` copies every `z-nile/<name>` except `engine.STATE`, so once c0283's last step wrote its list, four of five `record.spec` cases, a dispatch case and seven cases of AC7's own promoted specs went red, permanently on main.

**How to apply:** name the interface, not the file: any state file a layer creates is excluded from fixtures by that layer (`engine.STATE` and `engine.PATHSPECS`), and a spec that copies the tooling uses `engine.PATHSPECS`, not its own list. Run the layer's specs on a tree holding the siblings' prototypes after their last step.
