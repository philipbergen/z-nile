---
title: A guard that recognises a commit knows it by what it is, not by where a ref points now
when: design
tags: [git, guards, refs, stacks]
check: When a rule asks whether a branch still holds some special commit (a base commit, a bind, a start commit), does it identify that commit by something the commit carries (its subject, a trailer) over the branch's own range, or by a ref's current value? Can a stopped command, another clone or a person move or remove that ref without moving the branch?
---
A ref names one commit at a time; a branch can hold an older commit of the same kind. A guard that asks "is the current value of the ref an ancestor of this branch?" misses every earlier value, and one that falls back from origin's ref to the local one misses both in a clone that has neither.

**Why:** d0331 re-prep, design review 003 F1 (2026-11-19). `layerOneBase` refused a layer 1 that still held its raft's `<R>/base` commit by asking whether `origin/<R>/base` was an ancestor of the layer. A restack that stopped at layer 1 after `buildBase` had pushed a new base left the layer on the old base commit; once the base raft landed, the guard saw nothing, and `finish` squashed the old base commit and the base raft's old layer into the layer. The fix looks for the base commit's subject (`stack.baseSubject`, one function the writer uses too) in the layer's own range.

**How to apply:** for each such guard, list the commands that move the ref and the ones that move the branch, and the failure paths that do one and not the other. Prefer a mark the commit carries, written and read through one shared function.
