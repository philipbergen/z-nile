---
title: A rule's on-switch, and the record it compares against, are out of reach of the party it rules
when: design
tags: [guards, approval, records]
check: For each rule this design turns on by a marker (a front-matter line, a file, a flag), can the party the rule constrains edit or delete that marker, or the record the rule compares against, in a place the rule reads? If so, is the marker moved to a record that party cannot rewrite (a commit on origin/main), or is the edit itself refused?
---
A guard that a worker must pass is only as strong as the thing that turns it on. A marker in a document the worker commits, or a record the worker may delete, lets the worker switch the guard off, by mistake as easily as on purpose.

**Why:** f0399 design review 001 F3 and F12 (2026-11-16). The first draft made `done` ask every member for an approval only when the raft's document had a `lands: approved` line, and `done` reads that document from the layer, where the worker may edit it after finish. Deleting the line landed an unapproved issue. The same draft let a pushed guess be deleted from `guesses.md`, which brought an older approval back.

**How to apply:** for each marker, name who writes it and which tree each reader reads it from. Prefer a record on `origin/main` that the constrained party cannot rewrite (f0399 moved the marker into the ready commit's trailers). Where the record must live in the work tree, make the guard compare it with the pushed copy and refuse a removal (f0399's append-only check). Add a spec case that removes the marker and expects the guard to hold.
