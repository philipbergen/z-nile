---
title: A per-member copy of shared state is pinned at every reader
when: both
tags: [specs, wiring, state]
check: When the design gives each member its own copy of state the session shared (a maze with holes, a per-player table), does some case fail for each place that read the shared value if that one place keeps reading it, and for each reset (a new level, a new run) that must point every copy back, if that one copy is left? Better: is the copy derived from one source rather than reset by hand on each path, and does every cell of the reset table (kept cells included) name the mutant that was run for it?
---
Replacing one shared value with a per-member copy changes every reader at once in the design, but each reader is a separate line of code, and any one left on the shared value still type-checks and runs. Specs that check the copy as data (it has the hole) pass while the player, the ghosts or the shot still play in the old one.

**Why:** f0126 design review 001 F2: the player's move, the ghosts' maze and the shot's ray could each keep the session's plain maze, and every one of the 83 sequestered cases still passed; the specs only looked at `walls.opened`.

**How to apply:** list every reader of the old shared value (a search for it in the changed module), and give each a case where the copy's difference shows: the player walks into the hole, a ghost stands in it, the shot reaches into it. Where a behavioural case is out of reach, pin the call site's argument in the source and say why in the Rules row.

Resets are readers too: f0126 design review 002 F2 found that a fresh maze could leave the ghosts walking the holed copy (they then walked through closed holes) and every case still passed. A reset table whose columns are every per-member copy the reset owns, with a case per changed cell, catches it.

f0126 design review 003 F1: after round 2 added cases, three cells of the reset table were still unpinned (the ghosts on level 2, the ghosts after a death, the marks in a new run), because each copy had to be reset by hand on every trigger. The fix was structural: the holes became the one record, the member's maze is derived from them, and the ghosts are handed it every step, so nothing can be left behind; then each table cell names its row and mutant, "kept" cells included.
