# Portal game design

The source of truth for this project's product decisions, from the user's request of 2026-10-31 (captured in c0183). Every design in this project must agree with it. Changes happen through the user, never during execution.

## Design: Portal (`portal/`)
- The experience's **start place**, replacing Pickman's lobby place. Every game's game-over "back" returns here.
- **A carousel with one card per game** (Pickman, Snake, Invaders, Asteroids). Scroll with A/D, the arrows, the mouse wheel, a swipe, or the gamepad's shoulder buttons. Enter or A plays.
- **Each card shows:**
  - the title, a tagline and a live 3-D preview or art;
  - the **price badge: "5 R$" struck through, then "1 R$ SALE"**, or **"FREE GAME READY"** when that game's free hour is available, else "Next free game in mm:ss";
  - play buttons: PLAY, plus ARENA on Snake and 2 PLAYERS on Invaders and Asteroids;
  - **the game's hiscores** with tabs All-time / Today / This week. A row shows rank, name, score, the game's progress figure (Pickman level, Snake map, Invaders wave, Asteroids wave) and **revives used** ("—" for none). Below them, the "your best" line.
- **Purchase:** PLAY with no free game prompts the 1 R$ play product. The server grants exactly once (ProcessReceipt) and records an entitlement that the game place consumes on arrival. TeleportData is never trusted. The revive product is bought in each game place. Playtests show the same screens and charge nothing (f0145).


## Open item for the user (not blocking the captures)
- **"Permanent sale" pricing.** Showing 5 R$ struck through with a 1 R$ sale that never ends may conflict with Roblox's rules on misleading pricing. The portal's `game-design.md` records it as an open decision. The default is to build it as asked, with the badge text in one config table so it can change without code.
