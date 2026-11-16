---
title: A claim that one member's files pass another member's rule cites a run that held both
when: design
tags: [rafts, prototypes, evidence]
check: Does the prototype this claim cites contain the files the claim is about (`git merge-base --is-ancestor <prep> <proto>`), or was the rule run on the raft branch itself?
---
A raft's design can say "member A's check.sh passes member B's new rule" because B's prototype passed. But each prototype is cut from main before the other member's prep landed, so it never held A's files, and the claim was never run.

**Why:** R0062 design review 001 F1: the raft said c0139's check.sh passes c0141's prototype rule; neither prototype contained the other's prep. The reviewer ran c0141's scanner on the raft branch to settle it (4/4).

**How to apply:** when a raft claims cross-member compatibility, run the rule on the raft branch (or a copy of it with the prototype's code swapped in), and cite that run.
