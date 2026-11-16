# Asteroids game design

The source of truth for this project's product decisions, from the user's request of 2026-10-31 (captured in c0183). Every design in this project must agree with it. Changes happen through the user, never during execution.

## Game design: Asteroids (`asteroids/`)
Pillars: (1) Asteroids from the cockpit. (2) Deterministic Logic. (3) Readable: you always know what's behind you and what's about to wrap round.

**The field and view**
- The rules are 2-D: a flat, wrap-around field (leave one edge and you come back on the opposite edge), as in the arcade. Rocks tumble in 3-D for looks only.
- The camera sits in the ship's cockpit and looks along the ship's heading.
- **Wrap-around is drawn honestly:** the view shows the field tiled around you, so a rock about to wrap in from behind the far edge is visible at its true distance.
- A round **radar** in the HUD shows the whole field from above, with your ship at the centre. A **rear-danger glow** lights the screen edge when a rock or saucer shot closes in from behind (Pickman's glow idea).
- Keys: **A/D** rotate, **W** thrusts, **Space** fires, **Shift** jumps to hyperspace, and the **arrow keys** look round the cockpit. Gamepad: left stick rotates, RT thrusts, A fires, B hyperspace, right stick looks. Touch: ROTATE LEFT and RIGHT on the left, THRUST, FIRE and HYPER on the right.

**Rules (the classic)**
- **The ship** turns at a fixed rate and thrusts with inertia and slight drag, up to a top speed.
- **Shots:** up to 4 on the field at a time, each lasting about 1 s, and shots wrap round the field too.
- **Hyperspace** puts the ship at a random spot, with a 1 in 6 chance of exploding on re-entry (a tuning constant).
- **Rocks:** large splits into 2 medium, medium into 2 small, and small is destroyed. They score 20, 50 and 100. Ramming one costs a life (the rock still splits).
- **Waves:** wave 1 has 4 large rocks, and each later wave adds 2, up to 11. Clearing every rock starts the next wave after 2 s.
- **Saucers:** the large saucer (200) fires at random. The small saucer (1,000) aims at you, gets more accurate as the score rises, and appears more often in later waves. They cross the field edge to edge.
- **Lives:** 3, with one extra every 10,000 points. After a death the ship respawns at the centre once the centre is clear, protected for 2 s (shown by a flicker).
- **Game over:** the revive offer (1 R$ for 3 new lives, keeping score and wave).

**2 players**
- Both ships share one field, starting on opposite sides, with the same waves (the rock count is ×1.5).
- Each has their own score, lives and revives, so it is a race for the most points on shared rocks.
- Default: shots pass through the other ship (no friendly fire), but ships bounce off each other. The user may change either.
- If one player is out with no revive, the other plays on alone.
- **Pairing** works as for Invaders: a 2 PLAYERS card in the portal, then a party teleport into a reserved server.
