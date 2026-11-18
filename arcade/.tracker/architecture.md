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
  1. Hiscores: per-game store names (Pickman keeps today's names), a `revives` field on rows, one generic `Boards` server adapter. (f0197: `Logic/Hiscores` names a title's stores from its prefix, `Hiscores.names(prefix)`, where Pickman's prefix `""` gives today's `Hiscores`, `HiscoreEntries` and `HiscoreTop`; the progress figure keeps its stored name `level` for every title; `src/server/Boards.luau` is opened per title with `Boards.open(prefix)`; `src/shared/HiscoreGames.luau` lists every title's prefix and the name of its progress figure.)
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
  - The attributes are on `ServerScriptService` (where `Beta.project` writes them today), so they stay on the server. A place reads them with arcade's `Places.read(read)` (`src/shared/Places.luau`, a config module outside Logic, so the Travel feature names no game), its adapter passing `ServerScriptService:GetAttribute`; the names are `Places.attribute(name)` for each of `Places.NAMES` (f0199).
- The deploy scripts and the runtime-test runner (`--place <name>`) move to `portal/scripts/`. f0169 (live publish) builds on that.

**Unknowns that prep must settle with experiments:**
- **E1:** whether `rojo build`, `rojo serve`, `rojo sourcemap` and `luau-lsp` accept a `$path` outside the home.
- **E2:** cross-root requires in Roblox (expected not to work, hence the wiring rule above).
- **E3:** the DataStore budget for the portal reading 4 games × 3 boards. The fallback is a cached top-10 snapshot per board. **Settled by f0206** (design, 2026-11-15): the fallback is the design. Each portal server holds a snapshot of every board it has read (each title's three boards, read by the arcade's `Boards.serve` on a relay only the server can reach) and answers from it; an ask reads a board again only `REFRESH` (30 s) after that board's last read, under the portal's read allowance (the larger of 1.5 reads a minute per player in the server and 4 a minute, 12 at once: one per board, for a first visit) and only while the engine's request budget (`StandardRead`, `OrderedList`) holds a reserve for the wallet and the purchases above the read's most. A read is at most two `GetSortedAsync` (the arcade tries a rejected page size once more) and twelve `GetAsync`, and is charged so against the live budget; each read takes one token of the allowance, so in the usual case (one page try) the portal stays under the per-server sorted-read budget (5 + 2 per player a minute) whatever its clients ask, and the live budget check refuses a read the engine cannot cover. Across the experience (300 + 2 per concurrent user a minute) the portal spends 1.5 a minute per portal player, with at most 4 a minute for a server of one or two players and 12 once at each server's start. What `GetRequestBudgetForRequestType` reports on a fresh live server is not proven here (f0206 E8, an Observed step): if it starts below the reserve, the first boards wait for it. Proven on the real `Boards` by f0206's `budget.spec`.
- **E4:** ProcessReceipt retried in another place. Every place installs the same idempotent handler, with one play product per game or a pending-intent record.
- **E5:** a party teleport into a reserved server for 2-player Invaders. This can only be tested on Beta.
- **E6:** a Lune benchmark of a 24-player Snake arena (step cost and snapshot bytes) to set the player cap.
- **E7:** drawing the Asteroids wrap-around in first person: the cost of rendering the tiled field (nearby copies only) and whether it reads clearly in a Studio prototype.

## Features

### PaidPlay and Receipts (f0201)
The cost model every game shares (f0145's, per game: one free start per rolling hour per game, then 1 R$ a play, a revive for 1 R$, playtests never charge).
- `src/shared/Logic/PaidPlay` (a leaf: it requires nothing): the record of one player in one game (`free`, `plays`, `revives`, the last 50 receipt ids), the free-hour claim, the receipt ledger, the mode (`live`, `test`, `closed`) and the catalog's product map. It never names a game: a game is a catalog entry passed in.
- `src/server/Catalog.luau`: one entry per game (its name, title, its two stores, the attribute names of its two product ids). A new game is one entry and two Developer Products; no code changes.
- `src/server/Wallet.luau`: a player's records (stored in f0145's shape) through one `UpdateAsync` per decision (the arrival's claim, a revive used, a refund, a grant), the portal's passes (MemoryStore, only after a failed read), the run's revive count, and the guards, per player and game, that bound what one client can make it spend.
- `src/server/Receipts.luau`: installed by **every place** (E4): `ProcessReceipt` for every game's products (a receipt grants into the product's own game record by user id, wherever it is processed), the purchase prompts, and the test purchase screen's server side.
- `src/shared/Prices.luau`: the badge text ("5 R$" struck through, "1 R$", "SALE") and a revive's price ("1 R$", nothing struck; f0395), the one config table the portal and the screens print.
- `src/shared/TestPurchase.luau`: the test purchase screen, a client adapter module every place's client boots. It is the one client adapter in the library: it wires nothing into a game's screen, it stands in for Roblox's own purchase dialog in test mode. A place's own handlers of Return, KeypadEnter, ButtonA, Backspace, ButtonB and taps act through ContextActionService bindings below priority 3000, or skip processed input, or check `TestPurchase.isOpen()`; a device tracker is exempt. Its lines are rich text: a play's price line strikes the badge's struck price (f0395).
- Roblox's `ServerScriptService` attributes set by the publisher: `PaidPlay` (`"live"` for live mode) and each catalog entry's two product ids.

### Travel and Places (f0199)
- `src/shared/Logic/Travel` (the leaf, the copied rules): pickman's Travel, byte for byte (the teleport request, its timeout, cool-down and place-id check), so every place teleports by the same rules. Until c0200 switches pickman and deletes its copy, a change to either copy is made to both.
- `src/shared/Places.luau` (the place list and the attribute read, the one place in the library that names the experience's places; `src/server/Catalog.luau` names the games' paid-play entries): `Places.read(read)` reads `PortalPlaceId`, `PickmanPlaceId`, `SnakePlaceId`, `InvadersPlaceId` and `AsteroidsPlaceId` through the read a place's adapter passes in, each value through `Travel.destination`; a place that is not published is absent from the answer.

## Allowed dependencies

One `Consumer -> Provider` per line.

```deps
# PaidPlay and Travel are leaves
```
