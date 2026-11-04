# pickman

A first-person Pac-Man clone for Roblox, built with Rojo, strict Luau, and Lune for headless tests. New machine: see `SETUP.md`. The game is the `pickman` project, in `pickman/` (its `src/`, specs, Rojo projects and issues, `pickman/.tracker/`); the tooling that tracks and gates it is `z-nile/` (zz-rules skill, Projects). The arcade's projects are registered too (c0183): `arcade/` (the library every place shares), `portal/` (the experience's start place) and the games `snake/`, `invaders/` and `asteroids/`; each keeps its product decisions in `<name>/.tracker/game-design.md`, and the library its design in `arcade/.tracker/architecture.md`. Every project with code has the same home as `pickman/` (c0184): `check.sh`, `.luaurc`, `default.project.json`, `src/`, `tests/` and `skills/`, which the gate checks for each registered project (z-nile/README.md, A project's home).

**Non-negotiable:** no code without a tracker issue, and work is done only when its `check.sh` passes. **Every change is made in a git worktree under `.worktree/` and lands by pull request** (a capture lands with `./zn land`, after a local full gate); the main checkout is never edited, except by `./zn` itself (`ready`, `stop`, `sync`, and the board refresh after every publish or `land`), which only fast-forwards it, clears ignored files from item folders that left it, and writes ignored files (`prompt.md`, `.cache/board.html`) (zz-rules skill, Worktrees and Landing a change). Start execution with `/z-run <R-id>` in a session in the main checkout. Before doing anything, read the skill that applies. The skills hold all the rules.

**Subagents:** don't use `fork` subagents. Delegate to a plain subagent (general-purpose) with `model: "sonnet"` and a full brief. The exceptions are design and code reviewers, which the skills pin to Opus 5.5.

**Processes:** Run every probe, experiment, loop and background command you start yourself (anything that is not the gate, a check, a `./zn` command or the spec runner) through `./zn run --time <seconds> -- <command>`: it stops at its limit, when it ends and when you do. A PreToolUse hook refuses a bare `lune run` of a probe, a loop that never ends and a background job nothing bounds, and `./zn reap` stops what still leaks. A `/clear` ends the background commands of the conversation it clears (the SessionEnd hook stops its tool shells). A subagent stays open while its background commands run, and a command it started stops at its own `./zn run` limit (at most an hour) or at the session's end; the session-end reaper catches anything left. The zz-test skill's "Bounded commands" has the rest.

**No check may ever change the real repository.** Specs, `check.sh` files and the scripts they run change only throwaway fixtures under `.cache/`. The runner enforces it. On macOS it runs specs in a jail that denies every write to the repository outside `.cache`; a run that can't be jailed (inside another sandbox) refuses to start unless that sandbox already protects the repository. Everywhere it fences git into `.cache`, refuses ref updates and pushes into the real repository, runs one suite per checkout and project home at a time, and fails any run during which the remotes, config, branch or history changed. What it can't see (unjailed runs on Linux, `check.sh` files' own commands, work handed to processes outside the jail), review must catch (zz-test skill, "Specs never touch the real repository"). If its tripwire fires, stop and report: never repair the shared git configuration yourself.

The skills are z-nile's (`z-nile/skills/`) and each project's (`<project>/skills/`); `.claude/skills/<name>` links to each one (`./zn skills`). `z-nile/README.md` is the map: the flow, the five parts and every skill.

| Skill | Read when |
|---|---|
| `z-nile/skills/z-ticket/SKILL.md` | capturing a new feature, defect or chore |
| `z-nile/skills/z-design/SKILL.md` | designing one issue to prepared (includes the design review) |
| `z-nile/skills/z-raft/SKILL.md` | grouping prepared issues into rafts, recombining backlog rafts |
| `z-nile/skills/z-ready/SKILL.md` | readying a raft: claim, move to active/, write its prompt |
| `z-nile/skills/z-run/SKILL.md` | launching a readied raft from the main checkout (`/z-run R0010`) |
| `z-nile/skills/z-stop/SKILL.md` | undoing z-ready or aborting a raft |
| `z-nile/skills/zz-rules/SKILL.md` | creating, moving, committing or finishing tracked work |
| `z-nile/skills/zz-execute/SKILL.md` | executing a raft, the protocol z-run hands off to: one branch, one PR |
| `z-nile/skills/zz-review/SKILL.md` | acting as, or launching, the adversarial reviewer |
| `z-nile/skills/zz-arch/SKILL.md` | designing or writing the tooling: `z-nile/` (its `tests/` included), `zn`, `scripts/` |
| `z-nile/skills/zz-test/SKILL.md` | writing specs or `check.sh`, running the gate |
| `z-nile/skills/zz-stats/SKILL.md` | cost and rework reporting |
| `pickman/skills/pickman-arch/SKILL.md` | designing or writing anything in `pickman/src/` |
| `pickman/skills/pickman-test/SKILL.md` | writing pickman's game specs (with zz-test) |
| `<name>/skills/<name>-arch/SKILL.md`, for `arcade`, `portal`, `snake`, `invaders` and `asteroids` | designing or writing anything in that project's `src/` (each follows pickman-arch's rules with the changes it states, arcade's for a library) |
| `<name>/skills/<name>-test/SKILL.md`, for the same five | writing that project's specs (with zz-test and pickman-test) |

The `z-` skills are the pipeline, in order; the `zz-` skills are called from inside a step. The `zz-` and `z-` prefixes are z-nile's: a project's skills are named `<project>-…`.

Each skill keeps what reviews and mistakes taught it in its `lessons/` folder, and `./zn lessons` searches them. Every skill reads its own when it starts. z-design and zz-execute harvest every review finding into them. Any other new lesson depends on your role: the lead of a prep or raft writes it under the skill it improves, any other lead must capture a new lesson as an issue, and a subagent reports it to the agent that launched it.
