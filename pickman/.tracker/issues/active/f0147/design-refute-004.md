# Answers to design review 004 (f0147)

- F1: fixed: new case: after the bonanza's level starts and its long pill runs, a death and the respawn bring no second `PowerStarted`, frightened time 0, long hops kept; row M62 (the pill re-armed on a respawn while long hops are on), killed.
- F2: fixed: new case from the rejected option's side: with long hops on (level 2), the first seed whose pick rolls longer jumps grants nothing else (no power, pellets or shot, no fast pick, banner LONGER JUMPS); if the roll were re-rolled, no seed would roll it and the case fails; row M63 (the re-roll), killed. Lesson z-design/rejected-options-fail-a-case.
- F3: fixed: Behaviour 2 says an eaten ghost keeps its carry through the eyes' run and the house; the row is `reasoned` with its reason (observable only once, by at most one unit, after a full revive; no code writes the carry outside `speedOf` and `newGhost`).
- F4: fixed: chore c0196 (`depends_on: [f0147, f0158]`) is captured for the counter-against-ring unit case, and E8 and the Regression guard point at it; the f0143 hand-off is replaced by its reason (f0143's specs never build `GAME_CONFIG`, so they never see the ramp).
