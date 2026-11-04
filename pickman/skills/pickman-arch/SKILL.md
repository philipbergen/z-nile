---
name: pickman-arch
description: Code structure rules for pickman's game (strict Luau, pure Logic features vs thin Roblox adapters, require rules, dependency direction, server authority). Read before designing or writing anything in pickman/src/. The tooling's own rules are in zz-arch.
---

# Architecture (pickman)

## Layout (Rojo: `default.project.json` is the game place, `lobby.project.json` the lobby)
The game is pickman's, in its home `pickman/` (c0120): every path in this skill is relative to `pickman/`, where its specs and `check.sh` files run (`pickman/src/shared/Logic/...` in the repository). The arcade's projects extend this skill (`extends: pickman-arch`, c0184): a rule changed here changes theirs, so a change names its effect on them.
| path | Roblox location | contains |
|---|---|---|
| `src/shared/Logic/<Feature>/` | ReplicatedStorage.Shared.Logic | **pure game logic**: no engine access, fully unit-tested in Lune |
| `src/shared/` (outside Logic) | ReplicatedStorage.Shared | shared adapters: types, remotes, config tables. ModuleScripts only: `tests/place` enforces no Script or LocalScript under ReplicatedStorage |
| `src/server/` | ServerScriptService.Server | server adapters. `Main.server.luau` boots them |
| `src/client/` | StarterPlayerScripts.Client | client adapters: camera, input, rendering, HUD. `Main.client.luau` boots them |
| `src/lobby/server/` | ServerScriptService.Lobby (lobby place) | the lobby's server adapters: the start request and the teleport. `Main.server.luau` boots them |
| `src/lobby/client/` | StarterPlayerScripts.Lobby (lobby place) | the lobby's screen. `Main.client.luau` boots it |

Both places share `src/shared` as `ReplicatedStorage.Shared`. A further place is a further `<name>.project.json` and `src/<name>/`; the place harness (`z-nile/tests/lib/place.luau`, which every home's `tests/lib/place.luau` re-exports) reads its script roots from the project file, and the selector (`graph.placeInputs`) from every `$path` in the home's project files, so neither needs to learn it (c0185). A place maps the arcade library with `ReplicatedStorage.Arcade` = `../arcade/src/shared` and `ServerStorage.Arcade` = `../arcade/src/server`; those folders are the one place a `$path` leaves the home.

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
   - `.luaurc` aliases (`@logic`, `@shared`, `@arcade`, `@tests`, `@scripts`, `@znile`) are only for `tests/`, `scripts/` and `z-nile/`, because Roblox doesn't read `.luaurc`. `@znile` names `z-nile/` (an alias can't hold a hyphen). `@arcade` is the library's `src/shared` (`../arcade/src/shared`): a spec reaches an arcade feature as `@arcade/Logic/<Feature>`, the Roblox path `ReplicatedStorage.Arcade.Logic.<Feature>` without its service (c0185).
   - `src` reaches another Rojo root only through Roblox's built-in alias, across Rojo roots: e.g. an adapter's `require("@game/ReplicatedStorage/Shared/Logic/Session")`. Within one root, use relative paths or `@self`.
   - `@game` requires in `src` go only into ReplicatedStorage, and from a server file (one that every place of the home that maps it, each `*.project.json`, puts under a `ServerScriptService` or `ServerStorage` node, and at least one place maps) also into `ServerStorage` (`@game/ServerStorage/Arcade/...`, c0185). `ServerStorage` and `ServerScriptService` never replicate to clients, so a client or shared file requiring there fails at runtime; running client scripts are clones under `Players.<p>.PlayerScripts`, so a require into `StarterPlayer` loads a second, separate module instance. The resolvers can't tell these apart, so `tests/meta` enforces the rule through `graph.srcAliasAllowed`.
   - Logic never uses `@game`: the engine-word rule in `tests/meta` already rejects the word `game` in Logic files. `tests/place` and `tests/meta` both resolve `@game` through `default.project.json`. Logic never requires outside its home either: a relative path into another home resolves on disk (Lune, the graph) but not in Roblox's instance tree, and the instance-tree spelling resolves in Roblox but not on disk, so an arcade feature reaches Logic as a parameter an adapter passes in, and `tests/meta` fails any Logic require that resolves outside the home (c0185).
   - No dynamic requires in `src/`.
6. **Dependencies between features must be declared** in the ```` ```deps ```` block of `pickman/.tracker/architecture.md` (`.tracker/architecture.md` from pickman's home; `Consumer -> Provider`), and the graph must stay acyclic.
   - Adding an edge is a design decision, made in z-design and not during execution.
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
Before you start, read this skill's lessons: `./zn lessons --skill pickman-arch --full`. Each is a mistake made before, with the question that catches it.

A new lesson (from a review finding, a correction by the user, or a step that failed in a way a rule would have prevented) is handled by your role, not by the skill you are reading:
- **A subagent** (a stream, a reviewer, any agent working from a brief) never writes a lesson file or runs `./zn new`. It puts the candidate (the rule, why, and the question that catches it) in its review or final report.
- **The lead of a prep or raft** writes it in `<skills folder>/<the skill the lesson improves>/lessons/<slug>.md` (the real folder: `z-nile/skills/` for z-nile's skills, `<project>/skills/` for a project's, never through a `.claude/skills/` link, which git can't add through; format: zz-rules skill, Items), and records where it came from in its own `harvest.md`: review findings through the harvest (z-design step 5.3, zz-execute Phase 4 step 5), and anything else (a subagent's candidate, a correction by the user, a failed step) as `- note <what happened>: <lesson ids>`. It adds a note to an existing lesson when one fits, writes a new file only when none does, and commits both with its work.
- **Any other lead** (in the main checkout, a capture, or a metrics report) captures it: `./zn new issue c lesson-<slug> --project z-nile --desc "<skill>: <the rule>, because <what happened>; check: <the question>"` (z-ticket skill). The prep that takes the issue writes the file.
