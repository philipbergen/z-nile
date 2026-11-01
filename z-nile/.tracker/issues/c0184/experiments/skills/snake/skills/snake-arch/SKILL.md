---
name: snake-arch
extends: pickman-arch
description: Code structure rules for snake's game (first-person Snake: pure Logic features vs thin Roblox adapters, the same require rules as pickman's, server authority, and how it uses the arcade library). Read before designing or writing anything in snake/src/. The tooling's own rules are in zz-arch.
---

# Architecture (snake)

Snake is a game of the arcade, in its home `snake/`: every path in this skill is relative to `snake/`, where its specs and `check.sh` files run (`snake/src/shared/Logic/...` in the repository). Its product decisions are `snake/.tracker/game-design.md` and binding; its map of features and their dependencies is `snake/.tracker/architecture.md`.

## The rules are pickman's
Read `pickman/skills/pickman-arch/SKILL.md` first, and its lessons (`./zn lessons --skill pickman-arch --full`). Its Layout rows, Rules 1 to 8 and Design checklist are snake's too, as written, with the changes below. Snake keeps no copy of them: a change to a rule is made there once and applies here, and a rule that must differ for snake is stated in this skill instead. Pickman's examples (its maze, ghosts and lobby) are pickman's: the same rules apply to snake's own features.

## Layout (Rojo: `default.project.json` is the game place)
| path | Roblox location | contains |
|---|---|---|
| `src/shared/Logic/<Feature>/` | ReplicatedStorage.Shared.Logic | **pure game logic**, as pickman's |
| `src/shared/` (outside Logic) | ReplicatedStorage.Shared | shared adapters: types, remotes, config tables. ModuleScripts only |
| `src/server/` | ServerScriptService.Server | server adapters. `Main.server.luau` boots them |
| `src/client/` | StarterPlayerScripts.Client | client adapters: camera, input, rendering, HUD. `Main.client.luau` boots them |

`tests/meta/architecture.spec.luau` enforces the structural rules here: it runs pickman's meta spec from this home, so it reads `snake/src` and `snake/.tracker/architecture.md`.

## Changes to pickman's rules
1. **Arcade features are leaves that adapters wire in** (`arcade/.tracker/architecture.md`). Snake's Logic never requires arcade Logic: an arcade feature reaches Logic as a parameter (an RNG, a store, a travel status), and an adapter requires it through `@game/ReplicatedStorage/Arcade/...` (server adapters also `@game/ServerStorage/Arcade/...`). Until the cross-home gate exists (c0185), snake requires nothing from `arcade/`.
2. **The server is authoritative** (rule 7) for snake's state; the clients send intents and render.

## Design checklist (answer these in every snake issue's Design section)
Pickman's checklist, answered for snake:
- **Scalability**: the step cost and the snapshot bytes grow with the players in an arena and the arena's side; the cap is set by the load experiment (game-design.md, Players).
- **Maintainability**: the snake's step is data tables (maps, speeds, food values; game-design.md, Maps and Food).
- **Usability**: how it feels and the developer API; readable in first person: the minimap and the eased turns (game-design.md, Arena and view).
- **Touched modules**: the exact paths, used for spend attribution and for choosing affected tests.

## Lessons
Before you start, read this skill's lessons: `./zn lessons --skill snake-arch --full`. Each is a mistake made before, with the question that catches it.

A new lesson (from a review finding, a correction by the user, or a step that failed in a way a rule would have prevented) is handled by your role, not by the skill you are reading:
- **A subagent** (a stream, a reviewer, any agent working from a brief) never writes a lesson file or runs `./zn new`. It puts the candidate (the rule, why, and the question that catches it) in its review or final report.
- **The lead of a prep or raft** writes it in `<skills folder>/<the skill the lesson improves>/lessons/<slug>.md` (the real folder: `z-nile/skills/` for z-nile's skills, `<project>/skills/` for a project's, never through a `.claude/skills/` link, which git can't add through; format: zz-rules skill, Items), and records where it came from in its own `harvest.md`: review findings through the harvest (z-design step 5.3, zz-execute Phase 4 step 5), and anything else (a subagent's candidate, a correction by the user, a failed step) as `- note <what happened>: <lesson ids>`. It adds a note to an existing lesson when one fits, writes a new file only when none does, and commits both with its work.
- **Any other lead** (in the main checkout, a capture, or a metrics report) captures it: `./zn new issue c lesson-<slug> --project z-nile --desc "<skill>: <the rule>, because <what happened>; check: <the question>"` (z-ticket skill). The prep that takes the issue writes the file.
