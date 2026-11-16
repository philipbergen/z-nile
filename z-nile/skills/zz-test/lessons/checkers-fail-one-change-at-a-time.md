---
title: A checker with many checks gets a case per check, one change at a time
when: both
tags: [specs, mutants, runtime, checkers]
check: For a script or function that checks several things in turn (a runtime structure check, a validator, a guard), does each check have a case in which only that thing is wrong, so that deleting that one check fails a case? Or is every failing case a whole different input, which fails at its first difference and leaves the later checks unguarded?
---
A checker that runs its checks in order stops at the first failure. Cases that feed it whole wrong inputs (another place, an empty one) each fail at their first difference, so every check after it can be deleted and no case notices. The script then proves less than the design says it does.

**Why:** f0209 design review 001 F2. `portal/tests/runtime/structure.luau` checked a dozen things about the published start place: no lobby, the portal's server and remotes, the library on both sides, both place ids, paid play's mode and `CharacterAutoLoads`. Its spec failed it with an untold portal (stopping at `PickmanPlaceId`), pickman's lobby (stopping at `Lobby`) and pickman's game (stopping at `Server.Cards`). Deleting the `PortalPlaceId`, `PaidPlay`, `CharacterAutoLoads`, either `Arcade`, `Lobby` or `Snapshot` check left every case green.

**How to apply:** take the one input that passes (the published place) and, in a table, change one thing at a time: unset or corrupt one attribute, flip one property, unparent one child, add one forbidden child. Run the checker, expect it to fail with a message naming that thing, and undo the change before the next row; end by checking the input passes again, which proves every undo. Keep names that later issues may rename (modules, remotes) out of the spec's literals: the whole-input cases cover them together. Give each check a Rules row with the mutant "that check deleted", and run them.
