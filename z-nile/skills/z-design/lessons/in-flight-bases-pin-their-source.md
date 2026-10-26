---
title: A base cut from another prep's prototype pins what it was cut from
when: design
tags: [prototype, mutants, coordination]
check: Does every prototype base copied from another prep in flight record a hash of the diff and specs it was cut from, and does the mutation runner refuse when that prototype has moved, and run that prep's own specs on the unmutated base first? Are the hashed specs the ones that will be promoted (the prep worktree's `.tracker/issues/<id>/acceptance`), not only the prototype's copy, which can lag? Does the runner's hash check still pass just before the prep lands, since another prep's user decisions can reach its prototype before its documents or messages? While the other prep is still in review, is the base recut once as the last step before landing (not every round), so that the runner passes at the prep's final commit?
---
Another prep's prototype keeps changing while yours is reviewed. A base copied from it once looks current, and every spec passes against the stale copy while the real prototype has moved on.

**Why:** f0126 design reviews 008 and 009: f0109's prep changed its MazeView rule (`wallColorOf`) and Inky's colour after f0126's base was cut, so f0109's new place.spec case and colour checks failed on f0126's prototype, unseen, for a round; it was the third round in which a snapshot of a moving prep broke.

**How to apply:** record the SHA-256 of the other prototype's source diff and specs in the runner when the base is cut; have the runner refuse while that worktree exists and either hash differs; and before any mutant, run your specs and the other prep's own specs on the unmutated base, refusing unless all pass.

f0126 design review 010: the specs hashed were proto-f0109's copies; they matched f0109's prep this time, but a prototype's copy can lag behind the files that will be promoted.

f0126 design review 012 F1: f0109's new green (the user's 14, 64, 14) was already in proto-f0109's working tree while the brief still called it pending; the runner refused, as designed, and the base was recut.

f0126 design review 013 F1: f0109 moved again during round 3; each round's recut was dated by f0109's next round.
