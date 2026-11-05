# Arcade architecture

The shared library's design, from the plan the user approved on 2026-10-31 (captured in c0183). Every design that uses the library must agree with it; changing it is a design decision, made in z-design.

## Context
Pickman (first-person Pac-Man) is the only game in the repository today. The user wants it to become one game in an arcade:
- three new games, each its own project and directory: **first-person Snake**, **first-person Space Invaders** (the 2-player design first asked for as "asteroids"; project `invaders`), and **first-person Asteroids** (added by the user after the first draft; project `asteroids`);
- a new **portal** project: the landing place where you scroll between the games and see each game's hiscores;
- Snake is N-player (up to a high number, with a bigger world) and Invaders is 2-player;
- the cost model stays (f0145: one free game per hour, then 1 Robux per game, a revive for 1 Robux, playtests never charge), but each game is shown as **5 R$, struck through, on sale for 1 R$**, and every hiscore row shows **how many revives the run used**.

Decisions taken with the user (2026-10-31):
| Topic | Decision |
|---|---|
| Invaders | Pure Space Invaders (no splitting rocks). Project `invaders/`. |
| Asteroids | A third new game: first-person Asteroids. Project `asteroids/`. It is 2-player too, because the original request asked for 2-player asteroids. |
| Experience | One Roblox experience. The portal is the start place and replaces Pickman's lobby place, which retires. Pickman, Snake, Invaders and Asteroids are places in it. |
| Revives | Every board, Pickman's included, shows revives used. Pickman's f0145 "lives spent" becomes revives (captured as a scope change to f0145, which another session is preparing; f0145 itself is not edited here). |
| Free game | One free game per hour **per game** per player. |

This repo only takes work through its tracker (AGENTS.md: no code without an issue, every change in a worktree under `.worktree/`, landed by PR or `./zn land`). So this plan's **output is the tracker work**: the game designs below become each project's `game-design.md`, and the work becomes captured issues. Implementation then goes through z-design → z-raft → z-ready → z-run as usual.

## Technical skeleton

**A fourth new project: `arcade/`, a shared library.** It holds the code that every place uses. It is its own project with its own gate, specs and `arcade-arch` rules.
- `arcade/src/shared/Logic/<Feature>` maps to `ReplicatedStorage.Arcade`. `arcade/src/server` maps to `ServerStorage.Arcade`, which never replicates, so receipts and DataStore code stay off clients.
- Each place's `*.project.json` maps both with `"$path": "../arcade/..."`.
- Adapters require `@game/ReplicatedStorage/Arcade/...` (and `@game/ServerStorage/Arcade/...` from server roots). `graph.srcAliasAllowed` in `z-nile/lib/graph.luau` must allow that.
- **Game Logic never requires arcade Logic.** Arcade features are leaves that adapters wire in, and game Logic gets them as parameters (an RNG, a store, a travel status). That keeps pickman-arch rules 2 and 5. Lune tests reach arcade through an `@arcade` alias in each home's `.luaurc`.
- **What moves into arcade, in order:**
  1. Hiscores: per-game store names (Pickman keeps today's names), a `revives` field on rows, one generic `Boards` server adapter.
  2. Travel.
  3. PaidPlay: the per-game free hour as an atomic UpdateAsync, purchase decisions, an idempotent receipt ledger, and a `Receipts` adapter that every place installs.
  4. Rng.
  5. The Pad and Touch cores (generic folds only; each game keeps its key map).
  6. First-person Look.
  - The Session clock and intent limiter move only when Snake needs them.
- **Pickman migrates one feature at a time:** an arcade issue copies the feature and its specs, then a pickman issue switches the adapters and deletes the old copy. A raft never spans two projects.
- **Gate and selector, all in z-nile:**
  - `graph.affectedSpecs` re-runs a home's place specs when anything under any `$path` of its project files changes, another home's folders included (c0185; the old rule named `src/` and `lobby.project.json`).
  - `z-nile/affected.luau` matches every `*.project.json`.
  - `pickman/tests/lib/place.luau` moves into the shared harness and reads its script roots from the project file.
  - `tests/meta/architecture.spec` fails any Logic require that resolves outside its home.
- **Hard-coded pickman paths to generalize:**
  - `scripts/hooks/stop.sh:16`
  - `z-nile/tests/lib/cachepaths.luau:18`
  - the root `.luaurc`'s `logic` and `shared` aliases
  - `.github/workflows/deploy.yml` paths-ignore (otherwise every new tracker push triggers a deploy)

**Places and publishing.**
- `pickman/scripts/lib/beta.luau` and `deploy-beta.luau` handle exactly two places today. They become a manifest, `portal/experience.json`: one entry per place, with its project file and its env var.
  - `ROBLOX_BETA_PLACE_ID` is the portal (start place).
  - The games use `ROBLOX_BETA_PICKMAN_PLACE_ID` (the old `…_GAME_PLACE_ID` is still accepted), `…_SNAKE_…`, `…_INVADERS_…` and `…_ASTEROIDS_…`.
- Every place gets every place id as an attribute (`PortalPlaceId`, `PickmanPlaceId`, `SnakePlaceId`, `InvadersPlaceId`, `AsteroidsPlaceId`; 0 means not published, and the portal shows that card as "coming soon"). `LobbyPlaceId` becomes `PortalPlaceId`.
- The deploy scripts and the runtime-test runner (`--place <name>`) move to `portal/scripts/`. f0169 (live publish) builds on that.

**Unknowns that prep must settle with experiments:**
- **E1:** whether `rojo build`, `rojo serve`, `rojo sourcemap` and `luau-lsp` accept a `$path` outside the home.
- **E2:** cross-root requires in Roblox (expected not to work, hence the wiring rule above).
- **E3:** the DataStore budget for the portal reading 4 games × 3 boards. The fallback is a cached top-10 snapshot per board.
- **E4:** ProcessReceipt retried in another place. Every place installs the same idempotent handler, with one play product per game or a pending-intent record.
- **E5:** a party teleport into a reserved server for 2-player Invaders. This can only be tested on Beta.
- **E6:** a Lune benchmark of a 24-player Snake arena (step cost and snapshot bytes) to set the player cap.
- **E7:** drawing the Asteroids wrap-around in first person: the cost of rendering the tiled field (nearby copies only) and whether it reads clearly in a Studio prototype.

## Allowed dependencies

One `Consumer -> Provider` per line.

```deps
# no features yet
```
