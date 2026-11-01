---
title: "Fully enforced" means every clause of the lesson's check is decided
when: design
tags: [lessons, coverage, scope]
check: Does the named check decide every clause of the lesson's check question (not only today's instances of the guard, list or record), and is a thin marker (a text or stamp that shows a mitigation is present) marked part rather than full?
---
A lesson marked fully enforced leaves every step's reading and the build index, so any clause its check leaves undecided is asked by no one. Read the lesson's `check` clause by clause. If the mechanism names specific files, modules or instances, it decides "this X" only for those, and the lesson is partly enforced unless it is about those instances alone. A text or stamp that only shows a mitigation is present (a `Cost:` line, a mutant listed in a Rules row) decides a clause of a lesson whose substance is a reading: it makes the lesson partly enforced, never fully, and it keeps the lesson out of "not codifiable" too. Do not set a floor on the fully enforced count; review judges each mark.

**Why:** c0181 design reviews 002 F4, 003 F3, 004 F4 and F5, 006 F7, 008 F1 and F2, 009 F1 and F2: the plan's F rows kept leaving a clause (a general question answered only for the guards that exist today), and a floor on the full count made the executor mislabel rows to meet it.

**How to apply:** when you classify a lesson, write the clause the check leaves in the row, and make that the lesson's remaining `check`. After any change to a shared tool a row relies on, re-read every row that names it.
