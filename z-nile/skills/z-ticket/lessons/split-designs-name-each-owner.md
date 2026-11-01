---
title: Captures that split one design name each issue's own parts
when: both
tags: [capture, scope, design]
check: Does any captured Problem point at more of a design than its own outcomes (a whole game, "builds exactly what it says there"), and does every part of the design (each sub-section, or each bullet of a shared one, and each experiment) have exactly one owning issue, with the siblings named under Non-goals? When a gap is answered by handing the part to an existing issue, can that issue do it: do its dependencies, and the plan's order, put what it needs (the place, travel, a Beta publish) before it?
---
A capture's Problem is its scope, and no prep can narrow it. When one design is split among sibling issues, a pointer to the whole design makes each sibling's captured scope the whole design. Name the parts the issue owns, say the rest belongs to the siblings, and name them under Non-goals; a table of part → owner then shows the parts nobody owns (a game's server session, the far side of a teleport).

**Why:** c0190 design review 001 F4 and F6: 18 issues pointed at their whole game ("this issue builds exactly what it says there"), and no issue owned the games' running places or the 2-player match start.

**How to apply:** build the ownership table first, then write each Problem's pointer from its rows.

c0190 design review 002 F2: round 1 handed each game's party arrival and E5 to the 2-player issues, which the plan keeps pure Logic right after the scaffold, and split E5 across three issues none of which could run it on Beta; they moved to the view issues, with E5 owned by I3 after P4 and Z3.

c0190 design review 003 F1, F3, F4: the same gap a third time (the scores issues ran in a place they didn't depend on; the "rest of" lists covered only each issue's main file; Z3 and P5 both claimed the start place). One rule (an issue running in a place depends on the issue that builds it), walked over every row, and one record of each issue's parts per file, from which the lists are built, closed it.

c0190 design review 004 F1: walk the rule both ways: a view also depends on every rules issue whose state it shows or steers (S3 on S4), and a display only one issue's rule needs goes to that issue when the dependency would otherwise be a cycle. Keep a check that the ownership table and the script's records agree (E6-table.py).

c0190 design review 005 F1: when a capture adds a new front door to an existing game (a portal selling Pickman), walk the existing game's side too: who makes the game accept the new door, and does every issue that removes the old door (the lobby) depend on it?

c0190 design review 006 F1, F6: when a step is handed to several issues (each view publishing its own place), walk each one's dependency closure for what the step needs (the manifest, Z3), and apply the rule to every issue the new outcome touches (K3's arrival needs A2 like every arrival).

R0067 review 001 F1: build the "rest of" lines from the ownership table's owners, issues captured earlier included (f0187 owns a part of the arcade's map but was missing from its line).
