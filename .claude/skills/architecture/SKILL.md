---
name: architecture
description: Code structure rules for pickman (strict Luau, pure Logic features vs thin Roblox adapters, require rules, dependency direction). Read before designing or writing any src/ code.
---

# Architecture

## Layout (Rojo: `default.project.json` is the game place, `lobby.project.json` the lobby)
| path | Roblox location | contains |
|---|---|---|
| `src/shared/Logic/<Feature>/` | ReplicatedStorage.Shared.Logic | **pure game logic**: no engine access, fully unit-tested in Lune |
| `src/shared/` (outside Logic) | ReplicatedStorage.Shared | shared adapters: types, remotes, config tables. ModuleScripts only: `tests/place` enforces no Script or LocalScript under ReplicatedStorage |
| `src/server/` | ServerScriptService.Server | server adapters. `Main.server.luau` boots them |
| `src/client/` | StarterPlayerScripts.Client | client adapters: camera, input, rendering, HUD. `Main.client.luau` boots them |
| `src/lobby/server/` | ServerScriptService.Lobby (lobby place) | the lobby's server adapters: the start request and the teleport. `Main.server.luau` boots them |
| `src/lobby/client/` | StarterPlayerScripts.Lobby (lobby place) | the lobby's screen. `Main.client.luau` boots it |

Both places share `src/shared` as `ReplicatedStorage.Shared`. A further place is a further `<name>.project.json` and `src/<name>/`; `tests/lib/place.luau` (`place.load(project)`, its script roots) and the selector in `scripts/lib/graph.luau` must learn it too.

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

## Lessons
Before you start, read this skill's lessons: `scripts/tracker.sh lessons --skill architecture --full`. Each is a mistake made before, with the question that catches it.

A new lesson (from a review finding, a correction by the user, or a step that failed in a way a rule would have prevented) is handled by your role, not by the skill you are reading:
- **A subagent** (a stream, a reviewer, any agent working from a brief) never writes a lesson file or runs `tracker.sh new`. It puts the candidate (the rule, why, and the question that catches it) in its review or final report.
- **The lead of a prep or raft** writes it in `.claude/skills/<the skill the lesson improves>/lessons/<slug>.md` (format: tracker skill, Items), and records where it came from in its own `harvest.md`: review findings through the harvest (ticket-prep step 5.3, execute-raft Phase 4 step 5), and anything else (a subagent's candidate, a correction by the user, a failed step) as `- note <what happened>: <lesson ids>`. It adds a note to an existing lesson when one fits, writes a new file only when none does, and commits both with its work.
- **Any other lead** (in the main checkout, a capture, or a metrics report) captures it: `scripts/tracker.sh new issue c lesson-<slug> --desc "<skill>: <the rule>, because <what happened>; check: <the question>"` (make-issue skill). The prep that takes the issue writes the file.
