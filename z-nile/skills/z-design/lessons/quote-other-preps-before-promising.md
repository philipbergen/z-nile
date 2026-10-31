---
title: A promise made for another prep quotes that prep's own documents
when: design
tags: [coordination, dependencies, review]
check: Does every rule this design says another issue will follow ("f0146 keeps Y for the pick", "f0110 lands first") appear in that issue's current documents or specs, read from its prep worktree if it is in flight, and is any disagreement put to the user or to that prep before the design relies on it? And has `git worktree list` been rerun this round, so that every prep touching the Touched modules (not only those named in earlier rounds) is quoted with its current status? When this issue changes a number another prep quotes (a colour, a size), is it sent to that prep in the same round, the sending recorded, and the worktrees grepped for the old value?
---
An issue in flight elsewhere may already have settled the point differently. A design that assumes it will follow this one's plan writes a promise nobody keeps.

**Why:** f0126 design review 006 F2: f0126 bound the controller's Y in `View.KEYS` and said f0146 would keep it, while f0146's prep (in flight) had already put every gamepad button in its own exactly-pinned `Pad.BUTTONS`; the user then chose to land f0126 after f0146, as a row of that table. f0158 design review 001 F5: the capture asked the ring to clear the touch buttons, but f0158 never read f0110's in-flight prep, whose FIRE button sits under the ring on 480×320; neither issue said who checks the overlap. f0158 design review 002 F2: after round 1 made f0158 own FIRE's clearance, f0126's prepared PICK button, next in the same row, sat under the ring on seven screens and neither document said who owned it.

**How to apply:** for each issue the design leans on, find its prep worktree (`git worktree list`), read its current design and specs, quote what they say, and run their specs on a merged prototype. Where they disagree, ask the user or that prep before writing the promise.

f0126 design review 007 F2, F3: f0146's documents still recorded neither the Y reservation nor the every-input rule the refute said it was asked for; and two more preps (f0143, f0109, the latter called "not prepped" though it was) touched the same files unnamed. A promise that only another prep can keep is replaced by a check in this issue's own steps.

f0126 design review 012 F2: the user's brighter gold (255, 215, 0) left f0109.md quoting 255, 191, 0 and Inky at 45.4.

c0159 design review 002 F1: a chore wrote "f0158 must not spell it so" in its own Existing work only; f0158's documents, the ones its executor reads, said the opposite (its review called that spelling correct). A constraint one prep puts on another goes into the other item's own document, as a dated decision line, in the same round, or to the user when they disagree.
