---
name: architecture
description: Code structure rules for pickman (strict Luau, pure Logic features vs thin Roblox adapters, require rules, dependency direction). Read before designing or writing any src/ code.
---

# Architecture

## Layout (Rojo, `default.project.json`)
| path | Roblox location | contains |
|---|---|---|
| `src/shared/Logic/<Feature>/` | ReplicatedStorage.Shared.Logic | **pure game logic**: no engine access, fully unit-tested in Lune |
| `src/shared/` (outside Logic) | ReplicatedStorage.Shared | shared adapters: types, remotes, config tables. ModuleScripts only: `tests/place` enforces no Script or LocalScript under ReplicatedStorage |
| `src/server/` | ServerScriptService.Server | server adapters. `Main.server.luau` boots them |
| `src/client/` | StarterPlayerScripts.Client | client adapters: camera, input, rendering, HUD. `Main.client.luau` boots them |

## Rules (most are enforced by `tests/meta/architecture.spec.luau`)
1. **`--!strict` is the first line of every Luau file.**
2. **Logic is pure.**
   - Files under `src/shared/Logic` never mention `game`, `workspace`, `Instance`, `script` or `Enum`, and never touch the Roblox engine.
   - Time, randomness and input come in as parameters (for example `dt`, an RNG object, or intent values). That's what makes them deterministic and testable.
3. **Adapters are thin.**
   - They translate engine events into Logic calls, and Logic state into Instances.
   - Any branching an adapter does that could be wrong belongs in Logic.
   - Anything that has to be checked in Studio stays small and goes in the issue's Observed criteria.
4. **A feature is a directory with an `init.luau`, which is its public API.**
   - Other code requires a feature only through `init`: `require("../Maze")`, never `require("../Maze/Grid")`.
   - A feature's own files use `require("@self/…")` or `./…`.
5. **Requires are string literals, with relative paths, `@self` or `@game/ReplicatedStorage/`.**
   - Roblox and Lune resolve relative paths and `@self` the same way (not `@game`, which Lune can't resolve; that's why adapters are never required from `tests/`). Inside `init.luau`, `./X` means a *sibling of the feature directory*.
   - `.luaurc` aliases (`@logic`, `@shared`, `@tests`, `@scripts`) are only for `tests/` and `scripts/`, because Roblox doesn't read `.luaurc`.
   - `src` reaches another Rojo root only through Roblox's built-in alias, across Rojo roots: e.g. an adapter's `require("@game/ReplicatedStorage/Shared/Logic/Session")`. Within one root, use relative paths or `@self`.
   - `@game` requires in `src` go only into ReplicatedStorage. `ServerScriptService` never replicates to clients, so a client require there fails at runtime; running client scripts are clones under `Players.<p>.PlayerScripts`, so a require into `StarterPlayer` loads a second, separate module instance. The resolvers can't tell these apart, so `tests/meta` enforces the rule through `graph.srcAliasAllowed`.
   - Logic never uses `@game`: the engine-word rule in `tests/meta` already rejects the word `game` in Logic files. `tests/place` and `tests/meta` both resolve `@game` through `default.project.json`.
   - No dynamic requires in `src/`.
6. **Dependencies between features must be declared** in the ```` ```deps ```` block of `tracker/architecture.md` (`Consumer -> Provider`), and the graph must stay acyclic.
   - Adding an edge is a design decision, made in ticket-prep and not during execution.
7. **Server is authoritative** for game state: score, pellets, ghost positions, lives.
   - Clients send intents and render.
   - Anything a client could lie about is validated on the server.
8. **Types**:
   - Export public types from the feature's `init.luau` (`export type MazeGrid = …`).
   - Avoid `any` except at engine boundaries in adapters.

## Design checklist (answer these in every issue's Design section)
- **Scalability**:
  - What is the per-frame and per-tick cost, and how does it grow with the maze size, the ghost count or the player count?
  - What gets replicated, and how often?
- **Maintainability**:
  - Where does the next similar thing plug in: a new ghost, a new maze, a new power-up?
  - Is the behavior driven by data tables rather than by branching?
- **Usability**: two aspects.
  - How it feels for the player: readable, fair and responsive.
  - The developer API: small, typed, and hard to misuse.
- **Touched modules**: the exact paths, used for spend attribution and for choosing affected tests.
