---
title: The text a review judges against comes from the reviewed base, never from the branch under review
when: design
tags: [review, trust, limited-view]
check: For every review whose inputs include the design, the ask or the decisions, can the party under review edit those texts on its branch, and does the reviewer read them from the base (with the branch's edits shown as a patch to check) rather than from the working tree?
---
A review that compares a result with a text the author can rewrite proves nothing: a Design rewritten to match the code, or a `Scope decision` line the executor added, makes any implementation pass.

**Why:** c0262 design review 001 F3: the first draft of the final review's limited view read `design.md` and the decision lines from the document on the branch, and its diff left out tracker folders, so a Design edited during execution was approved against itself.

**How to apply:** read the judged texts with `git show <base>:<path>`, show the branch's edits to them as their own patch, label lines added on the branch as claims to check, and refuse when the base lacks the document.

**Also:** c0262 design review 002 F1: "read from the base, refuse when missing" deadlocked the gate for an emergent member, which exists only on the branch. Give items the branch creates their own route (accept them when their document says so, labelled), and take the gate's membership from one trusted place.
