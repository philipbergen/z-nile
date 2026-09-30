---
id: c0440
type: chore
title: Inside repo worktrees
slug: inside-repo-worktrees
raft: R0020
depends_on: [c0041]
emergent: false
design: reviewed
created: 2026-09-30
---

# c0440: Inside repo worktrees

## Problem
The user's rule (2026-09-30): **every job starts in a worktree directory inside the repo**, for example `.worktree/R0020`, never outside it. c0041 creates worktrees under `<repo>/.worktree/`, but nothing yet makes a *job* start there, and nothing says that a worktree outside the repo is wrong:
- A human starts an agent with `cd "$(scripts/tracker.sh worktree R…)" && claude`: two steps, easy to get wrong, and the agent runs wherever the shell happened to be.
- Earlier work used sibling directories (`../pickman-R0040`, `../pickman-R0020`), and the harness's own worktree feature puts them under `.claude/worktrees/`. Nothing flags a stray worktree outside `.worktree/`, and `worktree-prune` would never notice it.
- R0020's own bootstrap (before the tooling exists) still said to create `../pickman-R0020`.

## Non-goals
- **Changing where or how c0041 creates worktrees.** That is c0041's design (`.worktree/<R-id>`, `.worktree/<name>`); this issue builds on it.
- **Removing or moving a worktree outside `.worktree/`.** The prune command only warns; moving is the human's call (`git worktree move`).
- **Enforcing the rule for edits made by tools** (a hook denying edits in the main checkout). Still a separate follow-up (c0041 Non-goals).
- **Launching anything other than an agent command.** `launch` runs whatever command it is given; it doesn't know about models, permissions or prompts.

## Solution
- **`tracker.sh launch <target> [-- <command> [args…]]`**: ensures the worktree exactly as `tracker.sh worktree <target>` does, then runs the command (default `claude`) **with the worktree as its working directory**, forwarding stdin, stdout and stderr, and exits with the command's exit code. Arguments after `--` are passed through untouched.
- **`worktree-prune` lists strays**: any worktree of this repo that is not the main checkout and not under `<main checkout>/.worktree/` is reported on stderr as `warning: <path> is outside .worktree/ …`, and left alone.
- **The rule is written down**: the tracker skill's Worktrees section says every job runs in `<repo>/.worktree/<name>`, never outside the repo directory (no sibling directories, no `.claude/worktrees/`), and that humans start agents with `tracker.sh launch`. The launch line replaces the two-step `cd … && claude` in the make-prompt report, SETUP.md and AGENTS.md.
- **R0020's bootstrap** (the raft document, written in prep) creates `.worktree/R0020` inside the repo, excluded locally, instead of a sibling directory.

## Design

### The convention (from c0041)
Worktrees are created only under `<main checkout>/.worktree/`: `.worktree/<R-id>` for a raft (its branch is `R0010-<slug>`), `.worktree/<name>` for capture, prep, doc edits and workstream streams (`ws-<issue>`). `.worktree/` is gitignored, so it never shows in `git status` or in the gate.

### `scripts/tracker/main.luau`
- **`local function ensureWorktree(target: string): string`**: the body of c0041's `cmd.worktree` (classify, create or reuse), returning the absolute path instead of printing it. `cmd.worktree` becomes `print(ensureWorktree(pos[1]))`; `launch` calls the same function, so the two can't drift.
- **`cmd.launch`** parses its own arguments from the raw command line (the shared `flags` helper would swallow options meant for the agent): tokens before the first `--` are `<target>` (exactly one); tokens after it are `<command> [args…]`, default `claude`.
  1. `path = ensureWorktree(target)`. An unknown target, a bad name or a done raft fails here, before anything is launched.
  2. Print `launching <command> in <path>` to stderr.
  3. Run the command with `cwd = path` and stdin, stdout and stderr forwarded. If the program can't be started, fail `cannot run <command>: <reason>` (exit 1).
  4. Exit with the command's exit code.
- **`worktree-prune`** (c0041): after its existing loop, for each entry of `worktrees()` other than the first (the main checkout) whose path is not under `mainRoot() .. "/.worktree/"`, print `warning: <path> is outside .worktree/: move it with git worktree move, or remove it` to stderr. No exit-code change, nothing removed.
- **USAGE** gains `launch`.

### Docs (AC6 and JC1)
- **tracker skill**, Worktrees section: "Every job runs in a worktree under `<repo>/.worktree/`, never outside the repo directory: no sibling directories such as `../pickman-R0040`, and not the harness's `.claude/worktrees/`. Humans start an agent with `scripts/tracker.sh launch <target>` (for example `launch R0020`); an agent that is already running `cd`s with `scripts/tracker.sh worktree`." `launch` joins the lifecycle table.
- **make-prompt**: the report ends with `scripts/tracker.sh launch R…`, replacing `cd "$(scripts/tracker.sh worktree R…)" && claude`.
- **SETUP.md**, "Agents on this host", and **AGENTS.md**: the same launch line and the inside-the-repo rule in one sentence each.
- **`tracker/templates/prompt.md`** keeps the agent's first action (`cd "$(scripts/tracker.sh worktree {{RAFT_ID}})"`) for a session that was started elsewhere; it adds that the worktree lives under `.worktree/` inside the repo.
- **Nothing still says `.worktrees/` or a sibling path** (`../pickman-…`) in the skills, template, SETUP.md or AGENTS.md (AC6's negative grep).

### Scalability
- `launch` adds one process and the worktree check. `worktree-prune` adds one path comparison per worktree.

### Maintainability
- One function creates worktrees, for `worktree` and `launch`. The convention is one directory name and two path shapes.
- `launch` makes no assumption about the agent, so other agents (Grok, a shell) use the same entry point.

### Usability
- **Humans**: `scripts/tracker.sh launch R0020` replaces a two-step incantation, and the agent always starts in the right directory.
- **Agents**: the prompt's first action is unchanged, and strays are visible.

### Touched modules
- `scripts/tracker/main.luau`
- `tracker/templates/prompt.md`
- `.claude/skills/tracker/SKILL.md`
- `.claude/skills/make-prompt/SKILL.md`
- `SETUP.md`
- `AGENTS.md`

### Affected specs
`lune run scripts/affected -- scripts/tracker/main.luau tracker/templates/prompt.md` prints `ALL`, because `scripts/` forces a full run. New: `acceptance/launch.spec.luau`.

## Unknowns & experiments
- **E1 (prototype)**: can the designed `launch` and the stray warning satisfy the sequestered spec, and does the spec catch wrong implementations? Recorded in the Verification log (prototype stacked on c0420 and c0041; reverted).
- **E2 (run in prep: PASS)**: a worktree inside the repo directory doesn't disturb the main checkout or its gate. This PR was prepared in `.worktree/prep-inside-repo` with the directory excluded through `.git/info/exclude`, and `git status` in the main checkout stayed clean. In a scratch clone that held a full nested worktree (`.worktree/inner`, ignored through `.gitignore`), `git status` was clean and `scripts/check.sh --full` passed with exactly the same 346 specs as without it: no tool scanned the nested copy.
- **E3 (Observed, OC1)**: whether a session started in `.worktree/<id>` sees the same project memory and settings as one started in the main checkout. The repo's `CLAUDE.md`, skills and hooks are in the worktree, so they apply; per-project memory is keyed by the session's directory and may not be shared. If it isn't, that is worth a follow-up; it doesn't change this design.

## Regression guard
- **c0041's worktree spec** (paths `.worktree/<R-id>`, prune behaviour) and **c0430's** stay green; `ensureWorktree` is a move of existing code.
- **`tests/tooling/*`** are unaffected (no tracker behaviour outside `launch` and the prune warning changes).

## Test plan
`acceptance/launch.spec.luau` builds the usual scratch `.cache/launch-e2e/`: a seed clone of the repo (no origin, `main` forced, the working tree's tooling overlaid, tracker emptied) with raft `R0010` (`demo`) and issue `f0010`, then a bare `origin.git` and a clone `main/`. A fake agent is a shell script on `PATH` that writes its physical working directory and its arguments to `$FAKE_LOG` and exits with `$FAKE_EXIT` (default 0); `claude` and `agent` are two copies of it.

Cases (`spec case → AC`):
- `launch runs the command inside the raft's worktree` → AC1 (creates `.worktree/R0010` if missing, reuses it on a second launch)
- `launch defaults to claude and passes arguments after -- through untouched` → AC2 (arguments that look like options, for example `--from x --model y`, arrive unchanged)
- `launch returns the command's exit code and reports a command that can't start` → AC3
- `launch rejects an unknown target and a done raft and starts nothing` → AC4
- `worktree-prune warns about a worktree outside .worktree/ and leaves it` → AC5

### Rules and mutants
`run` rows were mutation-tested on the prep prototype (Verification log); `reasoned` rows were not run.

| rule | spec :: case | mutant it kills | checked |
|---|---|---|---|
| The command runs with the worktree as its working directory | `launch runs the command inside the raft's worktree` | run it in the caller's directory | run |
| The worktree is created or reused, never duplicated | `launch runs the command inside …` | always `worktree add` (fails on the second launch) | reasoned |
| Arguments after `--` pass through untouched; the default command is `claude` | `launch defaults to claude and passes arguments …` | parse the agent's arguments as `launch` options; no default | run |
| The exit code propagates; an unstartable command is an error naming it | `launch returns the command's exit code …` | always exit 0; swallow the error | run |
| An invalid target starts nothing | `launch rejects an unknown target and a done raft …` | launch before validating | run |
| A worktree outside `.worktree/` is warned about and left alone | `worktree-prune warns about a worktree outside .worktree/ …` | say nothing; remove it | run |
| The documents state the rule and the launch line | AC6 grep and JC1 | leave a sibling-path instruction | reasoned (a grep and a ruling, not a mutation) |

## Acceptance criteria

### Checked
- **AC1**: `tracker.sh launch <target> -- <command>` runs the command with the target's worktree (`<repo>/.worktree/<name or R-id>`) as its working directory, creating the worktree if needed and reusing it otherwise.
- **AC2**: Everything after `--` reaches the command untouched, even tokens that look like `launch` options; without `--` the command is `claude` with no arguments.
- **AC3**: `launch` exits with the command's exit code, and a command that can't start is an error that names it.
- **AC4**: An unknown target, an invalid name and a done raft are refused before anything is launched.
- **AC5**: `worktree-prune` warns on stderr about every worktree outside `.worktree/` (other than the main checkout), names its path, removes nothing, and doesn't warn about worktrees inside.
- **AC6**: The tracker skill states the inside-the-repo rule and documents `launch`; make-prompt, SETUP.md and AGENTS.md carry the launch line; and no skill, template, SETUP.md or AGENTS.md text still says `.worktrees/` or a sibling path (`../pickman-…`).

### Judged
- **JC1: no instruction starts a job outside `.worktree/`.**
  - **Pass**: in the tracker, execute-raft, make-issue, ticket-prep, make-prompt and review skills, the prompt template, SETUP.md and AGENTS.md, every instruction that starts a job (executing a raft, capturing an issue, prepping, editing docs, a workstream, a review) does so in `<repo>/.worktree/<…>`, by `launch`, `worktree` or an existing session's `cd`; none says to create or use a worktree elsewhere.
  - **Fail**: any instruction for a sibling directory, for `.claude/worktrees/`, or for starting a job in the main checkout. Quote it.

### Observed
- **OC1**: start an agent with `scripts/tracker.sh launch R…` on a real raft. Confirm it opens in `.worktree/R…`, that the repo's hooks and skills apply, and whether project memory is shared with the main checkout's sessions (E3). Note anything odd for a follow-up.

## Implementation steps
1. Extract `ensureWorktree` from `cmd.worktree` (no behaviour change; c0041's spec stays green). Commit.
2. `cmd.launch` and its USAGE line. Run AC1 to AC4. Commit.
3. The prune warning. Run AC5. Commit.
4. Docs: tracker skill, make-prompt, SETUP.md, AGENTS.md, the prompt template sentence. Run AC6. Commit.
5. `scripts/tracker.sh check c0440`, `scripts/check.sh --full`, `promote-check R0020`. Commit.

## Verification log
- **Prototype run (2026-09-30), reverted, never committed:** about 60 lines (`ensureWorktree` extracted, `cmd.launch`, the prune warning) stacked on the prototypes of c0420, c0041 (now with `.worktree/<R-id>` paths) and c0430.
  - All 5 launch cases pass; c0041's 28, c0430's 13 and c0420's 11 cases still pass with the new paths.
  - Seven planted mistakes each fail the case written for them: running the command in the caller's directory, dropping the arguments after `--`, an exit code that is always 0, a missing command that isn't an error, launching even when the target is invalid, a prune that says nothing about strays, and a prune that removes the stray.
  - Two spec bugs were found and fixed on the way: a `recorded()` helper built on `gmatch` returned extra empty lines (now `string.split`), and c0041's "never forces" case asserted the branch name in prune's stderr, which names the worktree path (now `.worktree/R0040`).
