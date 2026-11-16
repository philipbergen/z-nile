---
name: zz-arch
description: Code structure rules for z-nile's own tooling (the engine, the gate, the guards, the runner and harness, the tooling specs) - strict Luau on Lune, pure modules over texts with reads at the edge, one reader per format, guards that fail closed. Read before designing or writing anything in z-nile/ (its tests/ included), zn or scripts/. A project's own code follows its own skill (pickman-arch).
---

# Architecture (z-nile)

These rules are for the tooling: z-nile's files, which belong to no game. A project's code (pickman's `src/`) follows that project's own architecture rules, `pickman-arch` for pickman.

## Layout
| path | contains |
|---|---|
| `zn` | the command, at the repository root: it runs `z-nile/engine/main` |
| `z-nile/engine/` | the tracker engine. `main.luau` is the CLI: it parses arguments and does the git, file and process work. Every other module is one concern (`store`, `publish`, `projects`, `lessons`, `skills`, `trail`, …) |
| `z-nile/lib/bounded.pl`, `z-nile/lib/cpu.sh`, `z-nile/engine/reap.luau`, `z-nile/engine/boundcmd.luau`, `z-nile/guard-bash.luau` | the bounded runner, the reaper's rules, the hook's rules and its entry |
| `z-nile/lib/` | what the gate, the runner and the engine share: `ac.sh` (every `check.sh`), `fence.sh` and `git-hooks/` (the repository guards), `par.sh`, `sh.luau`, `graph.luau`, `changed.luau` |
| `z-nile/skills/` | z-nile's skills: the pipeline (`z-…`) and the skills called from inside a step (`zz-…`), linked into `.claude/skills/` by `./zn skills` |
| `z-nile/templates/` | the item, raft and prompt templates |
| `z-nile/projects.toml` | the project registry: each project's name and root (its home is the folder holding the root) |
| `z-nile/check.sh`, `affected.luau`, `roots.luau`, `setup.sh` | the gate, the affected-spec selector, the registry's shell reader and the bootstrap |
| `z-nile/tests/run.luau`, `lib/`, `tooling/`, `meta/`, `acceptance/` | the shared runner and harness, the tooling's specs, its structural rules and z-nile's promoted specs; they run from z-nile's home, `z-nile/` |

## Rules (the first and third are enforced by `z-nile/tests/meta/architecture.spec.luau`)
1. **`--!strict` is the first line of every Luau file**, `.tracker/` folders aside.
2. **The tooling is Luau on Lune.** Shell only where a shell must run it: `zn`, `check.sh` files, `ac.sh`, `fence.sh` and the hooks.
3. **Requires are relative, or through the root `.luaurc` aliases** (`@znile`, `@tests`, `@scripts`, `@lune`); `@znile` names `z-nile/`, because an alias can't hold a hyphen. Every require under `z-nile/tests/` resolves. Specs require only through aliases, because `done` moves them.
4. **Pure over texts, reads at the edge.** A module that parses, plans or checks takes text and data and returns results or problems; one `load` function, or `main.luau`, does the reading and writing. Spec the pure part directly and the command through a fixture (zz-test skill, "Specs never touch the real repository").
5. **One reader per format.** Each file format has one reader, and every command uses it: `projects.luau` for `projects.toml` (and `roots.luau` for the shell), `lessons.luau` for lessons and `harvest.md`, `skills.luau` for the skill folders and their links, `ids.luau` for the counter and the compaction map.
6. **Parsers refuse ambiguity.** A repeated single-value field, an unknown key or an out-of-shape value is a problem the parser names, with the file and the rule.
7. **Guards fail closed.** A guard acts only on its one explicit "no" answer and treats every other outcome as guarded. Configuration that widens a guard is read from `origin/main`, never from the working tree a branch can edit.
8. **Every refusal names the path, the item or the rule** it broke, so the person reading it can fix it without reading the code.

A Lune entry the gate runs, and so an agent may start bare, joins `TOOLING` in `z-nile/engine/boundcmd.luau` (the PreToolUse hook refuses every other `lune run` that is not wrapped).

## Design checklist (answer these in every tooling issue's Design section)
- **Scalability**: the git calls, file reads and processes per command, and how they grow with the items, the roots and the projects.
- **Maintainability**: where the next project, root, skill or command plugs in, and which one reader it goes through.
- **Usability**: the command line (usage text, refusals that name the rule) and every exhaustive list a new command or file kind must join (the main checkout's command list, the read-only set, the usage text).
- **Touched modules**: the exact paths, used for spend attribution and for choosing affected tests.

## Lessons
Search with `./zn lessons <terms>` when you are about to do something a lesson might cover.

A new lesson (from a review finding, a correction by the user, or a step that failed in a way a rule would have prevented) is handled by your role, not by the skill you are reading:
- **A subagent** (a stream, a reviewer, any agent working from a brief) never writes a lesson file or runs `./zn new`. It puts the candidate (the rule, why, and the question that catches it) in its review or final report.
- **The lead of a prep or raft** writes it in `<skills folder>/<the skill the lesson improves>/lessons/<slug>.md` (the real folder: `z-nile/skills/` for z-nile's skills, `<project>/skills/` for a project's, never through a `.claude/skills/` link, which git can't add through; format: zz-rules skill, Items), and records where it came from in its own `harvest.md`: review findings through the harvest (z-design step 5.3, zz-execute Phase 4 step 5), and anything else (a subagent's candidate, a correction by the user, a failed step) as `- note <what happened>: <lesson ids>`. It adds a note to an existing lesson when one fits, writes a new file only when none does, and commits both with its work.
- **Any other lead** (in the main checkout, a capture, or a metrics report) captures it: `./zn new issue c lesson-<slug> --project z-nile --desc "<skill>: <the rule>, because <what happened>; check: <the question>"` (z-ticket skill). The prep that takes the issue writes the file.
