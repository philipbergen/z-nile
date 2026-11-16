---
title: Fixture edits to an approved document keep its hash
when: both
tags: [fixtures, approval, documents]
check: When a fixture appends to an approved issue document (a ruling, an open list), does it write exactly what the tool writes, with no extra blank line before a new `##` heading, so the approval hash of the design is unchanged?
---
The approval hash covers the design's sections. An extra blank line before an appended heading changes the hashed text, and the tool refuses with "contract changed: design" for a reason the case never meant to test.

**Why:** c0248's prototype: a fixture that appended a section to an issue document with a blank line before its `##` heading changed the approval hash, and the command refused with "contract changed: design" instead of the refusal the case was about.

**How to apply:** append with the same separator the tool's own writer uses, and assert the refusal text the case is about, so a different refusal turns it red.

**Note (c0161's re-prep, 2026-11-15):** the other side of this rule: a fixture that edits a member's contract on purpose before `ready` (a redesign, a rewritten `check.sh`) must stamp its approval again (`seal.stamp`) after that edit and publish the stamp with it. Otherwise `ready` refuses with "contract changed since approval" (or "has no approval"), which fires before the record checks the case is about. c0161's `review-read` needed it in four cases, and the promoted `c0116/claims` still has one case red on main for this reason.
