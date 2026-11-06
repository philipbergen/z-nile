---
title: A digest that stands for a decision's result holds every input of the decision, or the decision's own output
when: both
tags: [digest, reuse, selection]
check: For each fact the reused decision reads (a merge-base, HEAD's tree, a ref), does changing only that fact move the digest? Where the inputs are many, does the digest hash the decision's output instead?
---
A whole-gate digest held the files, the base tip and the tools, while the affected selection also read the merge-base and HEAD's tree.

**Why:** R0081 review 005 F1: with the same tree at two HEADs (a squash of the branch onto main, or a commit undone in the index), a gate recorded where a failing spec was not selected was reused where it was, and printed `GATE PASSED` while `--fresh` failed. Even the Design's merge-base sha would not have closed the second case.

**How to apply:** hash the selection itself (the same function call the gate then runs) into the digest, keep the cheap inputs, and pin each way the selection can move without the files moving as an e2e case.
