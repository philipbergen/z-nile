---
name: arcade-arch
extends: pickman-arch
description: Code structure rules for the arcade library (the code every place shares - leaf Logic features, server-only adapters, and how the games and the portal wire it in). Read before designing or writing anything in arcade/src/. A game's own code follows its own skill (pickman-arch for pickman, snake-arch, ...).
---

# Architecture (arcade)

The arcade library is a project of its own, in its home `arcade/`: every path in this skill is relative to `arcade/`, where its specs and `check.sh` files run (`arcade/src/shared/Logic/...` in the repository). Its design is `arcade/.tracker/architecture.md` and binding; its features and their dependencies are listed there too (a ```` ```deps ```` block, when it has one). It has no game of its own: its `default.project.json` builds the library alone as a place (a game maps it into its own place: `ReplicatedStorage.Arcade` = `../arcade/src/shared` and `ServerStorage.Arcade` = `../arcade/src/server`, c0185).

## The rules are pickman's, with these changes
Read `pickman/skills/pickman-arch/SKILL.md` first, and its lessons (`./zn lessons --skill pickman-arch --full`). Its Rules 1 to 8 and Design checklist are the library's too, as written (`--!strict`, pure Logic, thin adapters, a feature is a directory with an `init.luau`, string-literal requires, declared dependencies, types), with the changes below.

## Layout
| path | Roblox location | contains |
|---|---|---|
| `src/shared/Logic/<Feature>/` | ReplicatedStorage.Arcade.Logic | **pure library logic**: no engine access, fully unit-tested in Lune |
| `src/shared/` (outside Logic) | ReplicatedStorage.Arcade | shared adapters: types, config tables. ModuleScripts only |
| `src/server/` | ServerStorage.Arcade | server-only adapters (stores, receipts): ServerStorage never replicates, so no client can read them |

There is no `src/client/`: a client adapter is the game's, because it wires a library feature into the game's own screen.

## Changes to pickman's rules
1. **A library feature is a leaf.** It knows no game and requires no game's Logic. A game's Logic never requires library Logic either: the feature reaches the game as a parameter (an RNG, a store, a travel status) and the game's adapters wire it in (`arcade/.tracker/architecture.md`, Technical skeleton).
2. **Per-game differences are parameters**, never a branch on a game's name: the store names, the destination place ids and the prices are passed in by the game's adapter.
3. **Server-only code is under `src/server/`** (stores, receipts, anything with a secret or a budget), and `src/shared/` holds only what a client may read.
4. **A feature moves in as a copy, then the game switches** (the plan's rule): an arcade issue adds the feature and its specs, and a pickman (or other game) issue switches the adapters to it and deletes the old copy. A raft never spans two projects.

## Design checklist (answer these in every arcade issue's Design section)
Pickman's checklist, answered for the library:
- **Scalability**: the cost per game and per player the feature adds, the DataStore requests it makes and their budget (the experiment E3), what it replicates.
- **Maintainability**: how a new game uses the feature without a change to it (a parameter or a config entry).
- **Usability**: the developer API a game's adapter calls: small, typed, hard to misuse.
- **Touched modules**: the exact paths, used for spend attribution and for choosing affected tests.

## Lessons
Before you start, read this skill's lessons: `./zn lessons --skill arcade-arch --full`. Each is a mistake made before, with the question that catches it.

A new lesson (from a review finding, a correction by the user, or a step that failed in a way a rule would have prevented) is handled by your role, not by the skill you are reading:
- **A subagent** (a stream, a reviewer, any agent working from a brief) never writes a lesson file or runs `./zn new`. It puts the candidate (the rule, why, and the question that catches it) in its review or final report.
- **The lead of a prep or raft** writes it in `<skills folder>/<the skill the lesson improves>/lessons/<slug>.md` (the real folder: `z-nile/skills/` for z-nile's skills, `<project>/skills/` for a project's, never through a `.claude/skills/` link, which git can't add through; format: zz-rules skill, Items), and records where it came from in its own `harvest.md`: review findings through the harvest (z-design step 5.3, zz-execute Phase 4 step 5), and anything else (a subagent's candidate, a correction by the user, a failed step) as `- note <what happened>: <lesson ids>`. It adds a note to an existing lesson when one fits, writes a new file only when none does, and commits both with its work.
- **Any other lead** (in the main checkout, a capture, or a metrics report) captures it: `./zn new issue c lesson-<slug> --project z-nile --desc "<skill>: <the rule>, because <what happened>; check: <the question>"` (z-ticket skill). The prep that takes the issue writes the file.
