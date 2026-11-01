# Snake game design

The source of truth for this project's product decisions, from the user's request of 2026-10-31 (captured in c0183). Every design in this project must agree with it. Changes happen through the user, never during execution.

## Game design: Snake (`snake/`)
Pillars: (1) Snake seen from the head. (2) Deterministic Logic, simulated headless, as in Pickman. (3) Fair and readable in first person: you always know where walls, bodies and food are.

**Arena and view**
- A square grid of tiles with a solid border. The camera sits low in the snake's head (eye about 0.6 tile up; walls and bodies are 1 tile high, so you can't see over them).
- A top-right **minimap** shows the whole arena: walls, food, your snake and every other snake. In first person this is what makes it fair.
- On a turn the camera yaw eases round over about 120 ms, so turns stay readable.
- Solo arena: 20×20. With N players, the side is `ceil(sqrt(400 + 250·(N−1)))`: 26 for 2, 34 for 4, 48 for 8, 66 for 16, 79 for 24. The size is fixed when a map starts.

**Movement**
- The snake moves one tile per step at the map's speed: 4 tiles/s real time on map 1, +0.25 per map, capped at 7.
- Intents are `Left` and `Right`, relative to the heading. There is no `Back`: reversing would be suicide. Up to **two turns are buffered**, so a quick Left, Left makes a U-turn over two tiles.
- **Boost:** while held, speed doubles and the snake sheds one tail segment every 0.5 s, never below 4 segments. A shed segment becomes a crumb (below). This is the move for cutting someone off.
- Keys follow Pickman's habits: **A/D** turn, **arrow keys** look, **Space** boosts. Gamepad: stick or D-pad turns, RT boosts. Touch: LEFT and RIGHT buttons on the bottom corners (44 pt minimum) and a BOOST button.

**Food**
- **Apple:** +1 length, 10 × map number points. There are always (players + 1) apples on the board.
- **Golden apple:** every 20 s one appears for 6 s. +3 length, 50 × map number points.
- **Crumbs:** when a snake dies in a shared arena, every other segment of its body becomes a crumb: +1 length, 5 points.

**Maps (the user's progression)**
- Map 1 is empty. **Map k has k−1 walls.** Each wall is one straight segment, horizontal or vertical, 3 to max(4, side/3) tiles long.
- **Walls never connect:** there is at least one empty tile all round every wall, diagonals included, and between every wall and the border. Spawn areas stay clear. Map 2's single wall is near the middle.
- Placement is a seeded roll with retries. If the walls don't fit, the arena grows by 2 tiles.
- **Goal length** for map k is 10 + 2k (12 on map 1). Reaching it ends the map: a 2 s "MAP CLEAR" with a bonus of 100 × k, then the next map, the snake reset to 4 segments, and a little more speed.
- **Shared arena:** the first snake to reach the goal **wins the map** (bonus 250 × k and a banner naming the winner). Everyone moves to the next map together, respawned at spread-out spawns with 4 segments.

**Death, lives and revives**
- A snake dies when its head enters a wall, the border, or any snake's body, its own included. Two heads meeting (the same tile, or swapping tiles) kill both.
- 3 lives. A death waits 1.5 s, then respawns the snake with 4 segments at the free tile farthest from every head, on the same map, after a 2 s "Ready".
- With no lives left: game over and the revive offer (1 R$ for 3 new lives, keeping score and map). In a shared arena the offer lasts 10 s while play goes on.

**Players**
- **Solo:** your own arena (Pickman's solo-instances model).
- **Arena:** a shared arena of up to 24 players (a tuning constant). It is the server's max players, set after a load experiment. You can join mid-map: you spawn at the safest tile after a 2 s Ready. The arena's size changes only at the next map.
- Each snake has a colour and a name above its head. The HUD shows length / goal, map, lives and score, plus a top-3 of lengths in the arena.
- Every run, solo or arena, goes to Snake's boards. A row shows score, map reached and revives used.
