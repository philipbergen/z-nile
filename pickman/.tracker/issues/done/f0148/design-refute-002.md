# Answers to design review 002 (f0148)

- F1: fixed: the order is f0148 first, then f0145 (agreed with f0145's lead, 2026-11-01); the Regression guard states it, quotes f0145.md at d1733dfc as the text that will change, and lists what f0145's prep commits first when it resumes (f0148 in its `depends_on`, Continues on `Sessions.made`, its pins loosened); z-raft does not ready f0145 before f0148 is done. f0148 changes nothing in Continues and names no override, because f0145 is not on main and lands after.
- F2: fixed: `Bests.CHOOSE_WAIT` = 5 s bounds the lobby's write (under Travel's 60 s cap); a later write leaves its choice for the next claim; E6 measures the lobby's write too; adapters.spec case (a silent store: the choice returns after 5 s; an answering store does not wait); rows A17, A18.
- F3: fixed: the Edge cases line now says level 1 (search: `grep -n "stores the best instead" f0148.md` finds nothing).
- F4: fixed: both "(1 until f0148)" in game-design.md read "(picked in the lobby, f0148)" (search finds none); f0147's docs spec still passes (its pinned prefixes are unchanged).
- F5: fixed: the stale "processed key" row is gone (L7 is the priority row only); rows A15 (no `player.Parent` recheck after the wait) and A16 (no claim of the players already in, with a new case); E3 records the full gate rerun after rounds 1 and 2.
