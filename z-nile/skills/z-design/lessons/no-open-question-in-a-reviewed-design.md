---
title: A design goes to review with no open question for the user in it
when: design
tags: [scope, review, user-decisions]
check: Does the document contain any "decision I need confirmed", "open question" or conditional step that waits on a person, and has it been put to the user (or turned into a recorded Scope decision) before the document is marked reviewed?
---
A reviewer cannot judge a design whose outcome depends on an answer nobody has given: every path through the question has to be designed, specced and mutant-checked, or the question has to be asked first.

**Why:** c0276 design review 001 F1: the Design said the served board's wiring "is a decision I need confirmed" while the document was marked `design: reviewed`; the wiring had no criterion, spec case or Rules row, so any implementation passed.

**How to apply:** when a design leans on an outcome that is not clearly inside the captured scope, put the question to the user (or into the report that goes to them) before the first review round, and keep it out of the Checked criteria until it is answered; never write "the executor decides".
