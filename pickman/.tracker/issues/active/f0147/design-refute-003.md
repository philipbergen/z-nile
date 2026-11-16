# Answers to design review 003 (f0147)

- F1: fixed: the carry case also resets on a new level and a new run, keeps the carry over a second power pellet (the next step 12, not 13) and over hunting steps between blue ones (12 again); Behaviour 2 states the power pellet rule; rows M58 (carries kept over a level or run), M59 (`Ghosts.power` resets them), M60 (a hunting step resets it), all killed.
- F2: fixed: put to the user (2026-11-01), who chose "Keep it, record it"; the Problem has the decision line and game-design.md's bonanza bullet says a longer-jumps roll from level 2 shows its banner and adds nothing (docs.spec needle). Consequences: none in code (the roll stays even among six).
- F3: fixed: hud.spec's clearance walks every field `Touch.buttons` returns (rectangles as they are, circles as bounding squares, anything else an error, at least two controls), so d0149's circles are checked whichever lands first; E7 records it.
- F4: fixed: a two-pick ramp's frame carries `picksGoal = 2` and the HUD says PICKS 0/2; row M61 (a fixed 10), killed.
- F5: fixed: E8 no longer asks an executor to edit another issue's sequestered spec: the issue that lands second pins the counter against the ring in a new unit case of its own (`tests/unit/Hud`); the reviewer's probe (no overlap on f0158's 15 screens) is recorded.
- F6: fixed: Implementation steps 3, 5 and 6 name `ghostRate`, `MAX_TOP`, the carry and `Session.speeds`' rates; step 6's "the carry" is now "the bonanza's carry into the next level".
- F7: fixed: game-design.md's Points line says points on level n are worth n times on the shipped game (docs.spec needle).
