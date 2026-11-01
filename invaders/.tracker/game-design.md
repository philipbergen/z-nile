# Invaders game design

The source of truth for this project's product decisions, from the user's request of 2026-10-31 (captured in c0183). Every design in this project must agree with it. Changes happen through the user, never during execution.

## Game design: Invaders (`invaders/`)
Pillars: (1) Space Invaders from the cannon's seat. (2) Deterministic Logic. (3) Readable: the whole field fits the view, and a field radar covers what doesn't.

**The field and view**
- The rules are 2-D. The classic vertical axis becomes depth: you stand on the ground at your base line looking down a long field, and the formation hovers ahead and advances toward you.
- The camera sits just behind and above the cannon and follows it from side to side. A small radar shows the whole field from above.
- Keys: **A/D** (or the arrows) move, **Space** fires. Gamepad: stick or D-pad moves, A or RT fires. Touch: LEFT and RIGHT buttons on the left, a FIRE disc on the right.

**Solo (the classic)**
- **Formation:** 5 rows × 11 aliens. The back row is worth 30, the middle two 20, the front two 10.
- **March:** the formation steps sideways. When it touches a side it advances one row toward you and reverses. It speeds up as it thins, and the beat sound speeds up with it.
- **Shots:** you have one shot on the field at a time. Aliens have up to 3 at a time: one aimed at your column, the others from random columns.
- **Barriers:** 4 bunkers between you and the formation. Each is a grid of blocks (8×6) that any shot erodes from either side, and that aliens marching through erase.
- **Mystery ship:** crosses the far end about every 25 s, worth 50, 100, 150 or 300.
- **Lives:** 3, with one extra at 1,500 points. A hit costs a life.
- **Invasion:** aliens reaching your base line is **game over at once** (as in the arcade). A revive gives 3 lives and restarts that wave from its starting depth.
- **Waves:** each cleared wave starts the next formation one row closer, as in the arcade, cycling after 8.

**2 players (the user's design)**
- The field is twice as deep. Player 1 is at the south end, player 2 at the north end, facing each other, each with 4 barriers in front.
- Each wave **flies in from the east side at the midline** in single file and **peels off alternately into two groups**: one forms up toward player 1, the other toward player 2 (two formations of 5 × 8). The fly-in takes about 3 s and aliens can be shot during it.
- Each group marches and advances toward its own player by the solo rules.
- **A shot crosses the whole field.** It can hit either group, the mystery ship, and **the other player's barriers**. Default: it can't hurt the other player (it stops at their base line). The user may change this.
- Each player has their own score, lives and revives. A wave ends when both groups are gone.
- If one player's game ends with no revive, their group flies off and later waves come to the remaining player as one solo formation.
- **Pairing:** in the portal, choosing "2 PLAYERS" on Invaders puts you on a waiting card. A second player in the same portal server (or a friend you invite) joins, and both are teleported together to a reserved server.
