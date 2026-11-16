# Answers to design review 003 (f0148)

- F1: fixed: a lobby.spec case with a store hook that yields: no teleport during the yield, a second press refused meanwhile, its level kept, one teleport after the resume; Behaviour 5 says the hook runs in the press's own thread (never spawned or deferred); rows L4b (`task.spawn`) and L4c (`task.defer`), killed.
- F2: fixed: with the user's approval (2026-11-01), f0148's prep committed `depends_on: [d0124, f0148]` and a Regression-guard bullet on f0145's prep branch (c746326c, pushed); f0145's lead was told; the Regression guard quotes the sha.
- F3: fixed: game-design.md's (prep) list and the Edge cases state the trade: a lobby write that misses its 5 s bound and lands after the claim is the next arrival's start; marked (prep) for the user to veto; docs.spec pins it.
- F4: fixed: the f0145 bullet is whole (`grep -n "Its prep gives$"` finds nothing).
- F5: fixed: docs.spec counts two "(picked in the lobby, f0148)" and no "(1 until f0148)".
