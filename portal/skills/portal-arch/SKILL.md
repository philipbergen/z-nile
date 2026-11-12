---
name: portal-arch
extends: pickman-arch
description: Code structure rules for the portal (the experience's start place - a carousel of the games with price badges and each game's boards - pure Logic features vs thin Roblox adapters, pickman's require rules, server authority, and how it uses the arcade library). Read before designing or writing anything in portal/src/. The tooling's own rules are in zz-arch.
---

# Architecture (portal)

The portal is the arcade's start place, in its home `portal/`: every path in this skill is relative to `portal/`, where its specs and `check.sh` files run (`portal/src/shared/Logic/...` in the repository). Its product decisions are `portal/.tracker/game-design.md` and binding; its map of features and their dependencies is `portal/.tracker/architecture.md`.

## The rules are pickman's
Read `pickman/skills/pickman-arch/SKILL.md` first. Its Layout rows, Rules 1 to 8 and Design checklist are the portal's too, as written, with the changes below. The portal keeps no copy of them: a change to a rule is made there once and applies here, and a rule that must differ for the portal is stated in this skill instead. Pickman's examples (its maze, ghosts and lobby) are pickman's.

## Layout (Rojo: `default.project.json` is the start place)
| path | Roblox location | contains |
|---|---|---|
| `src/shared/Logic/<Feature>/` | ReplicatedStorage.Shared.Logic | **pure logic**: what a card shows, the carousel's position, the badge for a game's state |
| `src/shared/` (outside Logic) | ReplicatedStorage.Shared | shared adapters: types, remotes, config tables (the badge text is one config table). ModuleScripts only |
| `src/server/` | ServerScriptService.Server | server adapters: reading the boards, granting a play, the teleport. `Main.server.luau` boots them |
| `src/client/` | StarterPlayerScripts.Client | client adapters: the carousel, the cards, input. `Main.client.luau` boots them |

`tests/meta/architecture.spec.luau` enforces the structural rules here: it runs pickman's meta spec from this home, so it reads `portal/src` and `portal/.tracker/architecture.md`.

## Changes to pickman's rules
1. **Arcade features are leaves that adapters wire in** (`arcade/.tracker/architecture.md`). The portal's Logic never requires arcade Logic: an arcade feature (the boards, paid play, travel) reaches Logic as a parameter, and an adapter requires it through `@game/ReplicatedStorage/Arcade/...` (server adapters also `@game/ServerStorage/Arcade/...`). The gate holds it (c0185): `tests/meta/architecture.spec` fails a Logic require that resolves outside the home, `@game/ServerStorage/...` is allowed from a server root only, and a spec reaches the library as `@arcade/Logic/<Feature>`.
2. **The server is authoritative** for what a player may do: a play is granted once, on the server (ProcessReceipt), and TeleportData is never trusted (game-design.md, Purchase).

## Design checklist (answer these in every portal issue's Design section)
Pickman's checklist, answered for the portal:
- **Scalability**: the DataStore reads for every game's boards (the experiment E3 in `arcade/.tracker/architecture.md`) and the cards on screen.
- **Maintainability**: a game is one entry of a config table (its card, its badge, its place id); the badge text is in one table so it changes without code (game-design.md, the open pricing item).
- **Usability**: scrolling by key, wheel, swipe and gamepad, and every badge state (game-design.md, Each card shows).
- **Touched modules**: the exact paths, used for spend attribution and for choosing affected tests.

## Lessons
Search with `./zn lessons <terms>` when you are about to do something a lesson might cover.

A new lesson (from a review finding, a correction by the user, or a step that failed in a way a rule would have prevented) is handled by your role, not by the skill you are reading:
- **A subagent** (a stream, a reviewer, any agent working from a brief) never writes a lesson file or runs `./zn new`. It puts the candidate (the rule, why, and the question that catches it) in its review or final report.
- **The lead of a prep or raft** writes it in `<skills folder>/<the skill the lesson improves>/lessons/<slug>.md` (the real folder: `z-nile/skills/` for z-nile's skills, `<project>/skills/` for a project's, never through a `.claude/skills/` link, which git can't add through; format: zz-rules skill, Items), and records where it came from in its own `harvest.md`: review findings through the harvest (z-design step 5.3, zz-execute Phase 4 step 5), and anything else (a subagent's candidate, a correction by the user, a failed step) as `- note <what happened>: <lesson ids>`. It adds a note to an existing lesson when one fits, writes a new file only when none does, and commits both with its work.
- **Any other lead** (in the main checkout, a capture, or a metrics report) captures it: `./zn new issue c lesson-<slug> --project z-nile --desc "<skill>: <the rule>, because <what happened>; check: <the question>"` (z-ticket skill). The prep that takes the issue writes the file.
