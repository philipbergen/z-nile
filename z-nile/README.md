# z-nile

```mermaid
flowchart LR
  subgraph skills["skills: z-nile/skills, project/skills"]
    direction LR
    zticket["z-ticket"] --> zdesign["z-design"] --> zraft["z-raft"] --> zready["z-ready"] --> zrun["z-run"]
    zready -.-> zstop["z-stop"]
    zrun -.-> zstop
  end
  steps["zz-execute, zz-review, zz-rules, zz-arch, zz-test, zz-stats (called from inside a step)"] -.-> skills
  tracker[("tracker: ./zn, z-nile/.tracker, pickman/.tracker")]
  models[".models.toml: the model and CLI per step"]
  dispatcher["dispatcher: ./zn dispatch"]
  board["board: ./zn board, a tab per project"]
  skills <--> tracker
  models --> dispatcher
  dispatcher -->|"runs a skill on an item"| skills
  tracker --> board
  board -->|"copies the next command"| skills
```

z-nile is the tooling that tracks, designs, gates and delivers the work of every project in this repository. A game is a project: pickman is one, in `pickman/`. The arcade adds five more (c0183): the shared library `arcade`, the start place `portal`, and the games `snake`, `invaders` and `asteroids`, each in its own folder. z-nile belongs to no game.

## How it should work
Status labels, on every sub-section below and every roadmap row (*captured* is this section's word for an issue that exists as a draft): **exists** (built and on `main`), **designed** (its issue's Design is ready, not built), **captured** (an issue exists as a draft with no design yet). Nothing below is described as built unless it is labelled *exists*. A feature's PR changes its own roadmap row and every label that names it. Older notes in this file written "(cNNNN, planned)" predate these labels and mean not built.

```mermaid
flowchart LR
  subgraph eng["engineer end: any AI CLI, interactive"]
    direction TB
    cap["capture, sharpen ideas, review designs"]
    res["resolve escalations: ./zn resolve"]
  end
  stack[("ranked stack on origin/main: tickets, rafts, state")]
  subgraph wrk["worker end: any AI CLI, headless, same or other host"]
    direction TB
    loop["./zn work: claim top item, run next step, record spend"]
    rev["cross-model review"]
  end
  eng --> stack
  stack --> loop --> rev --> merge["merge when green"]
  loop -. blocked .-> esc["escalation.md, status blocked"]
  esc --> res
  res --> stack
```

### Two ends, one stack
- **The engineer end.** You sit in any AI CLI (`claude` and `agent` today; another CLI once its skill support is checked, c0115) in the main checkout and run the front of the pipeline: `z-ticket` to capture, `z-design` to sharpen an idea into a prepared issue, the design reviews. Everything you produce is tracker state landed on `main`: by pull request, or, for a capture or a claim, pushed straight to it (`./zn land`, `./zn status`). *exists*
- **The worker end.** A wrapper launches any supported AI CLI headless, on the same host or another, takes the next item from the stack and moves it forward: design, raft, ready, run, review, gate, merge. One command, `./zn work`, loops until the stack is empty or every remaining item is blocked. *captured* (c0253), on top of c0117's dispatcher (`./zn dispatch`, its chain, `.models.toml`, quota fallback, spend), which is *designed* (c0117).
- **The only shared thing is `origin/main` and GitHub.** No daemon, no queue server. A worker on another machine needs a clone, its CLIs and a bot credential; the engineer sees it work on the board. *captured* (c0254)

### Order
Tickets have no order today. They should: every issue and raft gets a `rank:` (integer, lower first; not the `rank` of `.models.toml`, where a higher one wins). *captured* (c0249)
- The next item is the lowest rank among items whose `depends_on` are all done and whose status is claimable. `depends_on` is a hard constraint; `rank` only orders what is free.
- Lost work comes before rank: a claim whose heartbeat went quiet (`./zn lost`) is taken before anything not yet started, whatever its rank. *exists* (c0265)
- z-ticket and z-design append by default. You move things with `./zn rank <id> top|after <id>`. A raft takes the best rank of its members. The board shows the stack in order.

### Claiming across hosts
A worker claims an item by landing the status change on `origin/main`, as `status <id> preparing` and z-ready already do. The push is the lock: a lost race means taking the next item. Each step runs in its own worktree under `.worktree/` on the worker's host. The worker's identity (host, CLI, model) goes on its spend rows. *captured* (c0254) (the claim itself *exists*)

### Autonomous delivery
Unless something blocks, an item is designed, design-reviewed, rafted, executed, code-reviewed, tested and merged with no human in the loop. Rigor does not drop: tests first, sequestered `check.sh`, the full gate once at the merge, and a merge only when the PR is green and regression-free. This replaces c0117's "stops at a merge" gate with the dispatcher merging after its own checks. *captured* (c0252)

### Reviews by different models
- A reviewer should run on a different model family than the author, and successive rounds rotate (author Sonnet, round one Opus through `claude` or `agent`, round two `grok-4.7-xhigh` through `grok`). `.models.toml` names a review pool; the dispatcher takes the first member whose family differs from the author's and the previous round's reviewer. *captured* (c0251); what c0117 designs (*designed* (c0117)) fixes only which model reviews per CLI.
- Same-family review (Opus reviewing Opus) is fine, but it is the fallback and never the only choice: it runs only when no different-family CLI can (out of tokens or quota, CLI missing). It never blocks the chain.
- Every review records its model and whether it was a fallback. The board flags fallback reviews so you can ask for a cross-model re-review when tokens return. Every finding is still harvested into a skill's lessons.

### Escalation to the human
A worker never guesses past a wall; it escalates formally. *captured* (c0250)
- **State.** The item goes to status `blocked` on `origin/main`, so every host and the board see it, with a `blocked:` reason from a closed list:

  | reason | meaning |
  |---|---|
  | `review-exhausted` | N review rounds, findings still open |
  | `design-gap` | the work needs a tool, library, dependency or scope the design did not cover |
  | `needs-decision` | an ambiguity only the human can settle |
  | `red-gate` | N fix attempts and the gate is still red |
  | `quota` | every CLI failed on quota |
  | `tripwire` | a guard fired (foreign refs, unvetted push to `main`) |

- **The note.** `escalation.md` in the item's folder, landed with the state: reason, what was tried, the open findings or error verbatim, the options with a recommendation, and the exact resume commands. It is in git, not `.cache`, so it works across hosts and replaces c0117's local `questions.md`.
- **The worker moves on.** It parks the branch and PR, releases its claim, and takes the next unblocked item that does not depend on the blocked one.
- **You resolve.** The board lists blocked items first with the reason and the question. `./zn resolve <id> <decision>`, where the decision is `amend-design` (back to z-design with the note as input), `approve` (for example accept the new dependency, recorded in the design), `split` (carve out an issue), `retry` (more rounds or attempts) or `abort` (z-stop). The decision is committed to the item, and it rejoins the stack at its old rank.
- Nothing else stops a worker.

### Trust
*designed* (c0117).

Workers run with a bot credential that can push branches and open PRs but cannot merge or bypass `main`'s protection; only the dispatcher merges. The guards (git/gh wrapper, publish broker, tripwire, watermark) catch honest mistakes and casual misbehaviour; none is a boundary against a determined agent (c0117).

### Roadmap
| piece | issue | state |
|---|---|---|
| work heartbeat, `./zn beat`, `./zn lost` | c0265 | exists |
| take over a lost claim (`status <id> preparing`, `beat --adopt`) | c0274 | exists |
| automatic heartbeats (first beat, every command, long commands, the background beater, the dispatcher) | c0275 | exists |
| discard and recover a worktree (`worktree --takeover`, numbered copies, the discard marker, the sweep) | c0277 | exists |
| `.models.toml`, dispatcher, chain, quota fallback, bot credential | c0117 | designed |
| board, a tab per project | c0118 | designed |
| remote runtimes (`claude-cloud`, `grok-bot`, `cursor-app`) | c0142 | captured |
| a raft delivered as a stacked PR set, one layer per issue | c0248 | captured |
| `rank`, `./zn rank`, `./zn next` | c0249 | captured |
| `blocked`, `escalation.md`, `./zn resolve` | c0250 | captured |
| cross-model review pool, same-family fallback | c0251 | captured |
| the dispatcher merges a green layer | c0252 | captured |
| `./zn work` pull loop | c0253 | captured |
| workers on several hosts, worker identity in spend | c0254 | captured |
| `./zn land` usage and a cheap retry | c0258 | captured |

c0248 to c0254 are meant to be one raft once designed, delivered as a stacked PR set: layer 1 is c0248 on `main`, each next layer on the one below, in that order, merging bottom-up. c0258 (a capture lands with `./zn land`, which should print usage on `--help` and retry cheaply when `main` moves) is separate.

### Stacked delivery
The general model (*captured* (c0248); today a raft is one branch and one PR): a raft is delivered as a **stacked PR set**, one layer (a branch and a PR) per issue, in the raft's Order. Each layer is reviewed and gated on its own diff; layers merge bottom-up, each retargeted to `main` as the one below merges. A one-issue raft is a stack of one. A blocked layer stops the layers above it, not the ones below.

## The five parts
- **The tracker.** `./zn` at the repository root runs the engine in `z-nile/engine/`. Each project keeps its issues and rafts in its own root, `<project>/.tracker/` (z-nile's in `z-nile/.tracker/`), listed in `z-nile/projects.toml`. One counter, `z-nile/next`, numbers every project. The rules are in the zz-rules skill.
- **The skills.** z-nile's skills live in `z-nile/skills/`, and a project's own in `<project>/skills/`. `.claude/skills/<name>` is a committed relative link to each, written by `./zn skills` and checked by `./zn skills --check` in the gate. The `z-` skills are the pipeline, in the order above; the `zz-` skills are called only from inside a step. Both prefixes are z-nile's: a project's skills are named `<project>-…`.
- **The dispatcher.** `./zn dispatch <id>` runs the chain on an item from its tracker state (ticket, design, raft, ready, run), headless and unattended, up to the run's pull request: script steps (`ready`, `raft-plan`, `spend`, …) it runs itself, model steps on the CLIs `.models.toml` orders, moving down the order only when a CLI fails on quota. It stops at a merge gate, at a step's `questions.md` and at a failure, and records each step's tokens and model on its spend row. Agents run with `z-nile/bin/git` and `gh` first on their PATH. Agents run as your own OS user, so its guards (the wrapper, the publish broker, the tripwire, the watermark, the merge gates) detect honest mistakes and casual misbehaviour; none of them is a security boundary against a determined agent. The watermark file is shared by every dispatcher of the repository and only moves forward. The rules are in the zz-rules skill, Dispatch.
- **`.models.toml`.** It says, per model step and CLI (`claude`, `grok`, `agent`), the model, its rank, runtime and `max_tokens`, and the CLI priority order, stacking from the repository root down to the work, as `.gitignore` does.
- **The board.** `./zn board` writes the whole tracker as one page (`.cache/board.html`): a tab per project, its issues as cards in the pipeline's columns with each raft a band behind its members, the review charts, and the next command for each row (c0118). `./zn board --serve` (c0121, planned) serves the same page live.

## Skills
| skill | step | what it does |
|---|---|---|
| `z-ticket` | 1 | captures a feature, defect or chore as a backlog issue, in a `capture-<slug>` worktree, landed with `./zn land` |
| `z-design` | 2 | designs one issue to `design: ready` and `prepared`: Design, `size:`, `check.sh`, acceptance specs, experiments, the adversarial design review. It makes no raft |
| `z-raft` | 3 | groups prepared issues into rafts (`./zn raft-plan`, or as asked), writes each raft's Theme, Order and interfaces, and runs a short coherence review for a raft of several issues |
| `z-ready` | 4 | from the main checkout: claims a prepared raft, moves it to `active/`, writes its `prompt.md` |
| `z-run` | 5 | launches a readied raft from the main checkout (`/z-run R0010`): reads its prompt, enters its worktree, hands off to zz-execute |
| `z-stop` | any | gives a readied or started raft back; its branch and PR stay |
| `zz-execute` | from z-run | the execution protocol: one branch, one PR, experiments, tests first, review, done, merge |
| `zz-review` | from z-design, z-raft and zz-execute | the clean adversarial reviewer: design, raft, stream and code modes |
| `zz-rules` | every step | the tracker's rules: ids, roots, lifecycle, worktrees, landing, spend |
| `zz-arch` | design and build of the tooling | the tooling's code structure |
| `zz-test` | every step | the gate, the spec runner, `check.sh`, sequestration and the guards |
| `zz-stats` | on demand | cost per issue and the rework rate |
| `pickman-arch`, `pickman-test` | pickman's design and build | pickman's code structure, and its game spec tiers |
| `arcade-arch`, `arcade-test`, `portal-arch`, `portal-test`, `snake-arch`, `snake-test`, `invaders-arch`, `invaders-test`, `asteroids-arch`, `asteroids-test` | the arcade's design and build (c0184) | each project's code structure (pickman's rules, with the changes the skill states) and its spec tiers |

## A project's home
A project with code has a home, `<name>/`, which also holds its `.tracker/` root. `pickman/` and the arcade's five (`arcade/`, `portal/`, `snake/`, `invaders/` and `asteroids/`, c0184) have the same home; the gate checks it for every project of `z-nile/projects.toml` except z-nile, whose home holds the tooling:
- `check.sh`: the project's gate, `exec bash "$(dirname "$0")/../z-nile/check.sh" --project <name> "$@"`.
- `.luaurc`, with the aliases `logic`, `shared`, `tests` and `znile` pointed at the home's own folders (`znile` at `../z-nile`), `arcade` at the library's `src/shared` (`../arcade/src/shared`, the same line in every home, the library's included), and `stylua.toml` and `selene.toml`, the root's.
- `default.project.json`, and any other `*.project.json`: the places the home builds. Every `$path` is a folder of the home, but for the library's two (`../arcade/src/shared` and `../arcade/src/server`), which the default place maps as `ReplicatedStorage.Arcade` and `ServerStorage.Arcade` in every home (c0185). A `$path` is a string or `{"optional": "<path>"}`; any other value is reported, because the reader of the project files cannot follow it. The rule also asks Rojo itself what each project file builds, reports a file Rojo reads from outside the home and the library's two folders, a library file Rojo puts anywhere but at its node, and a project file Rojo loads from a mapped folder.
- `src/shared/Logic/` and `src/server/`, and `src/client/` for a place with a client.
- `tests/run.luau` (the shared runner, run from the home), `tests/lib/t.luau` and `renamed.luau` (its re-exports), and `tests/meta/architecture.spec.luau`, `fence.spec.luau` and `home.spec.luau`: the structural rules of pickman-arch, the repository-fence spec and this home rule, each run from the home. `tests/lib/place.luau` (the shared place harness, re-exported) and `tests/place/library.spec.luau` (the shared place spec, called with it) are the home's place tier.
- `skills/<name>-arch/SKILL.md` and `skills/<name>-test/SKILL.md`, linked into `.claude/skills/` by `./zn skills`.
- In its root, `architecture.md`, with one `deps` block.

A new project with code needs its registry entry, its root and `deploy.yml` entry (zz-rules skill, Projects) and this home. Make the home by copying a sibling's and renaming it; the gate's home rule names whatever is missing.

## Design checklists
z-design reads the checklist for the issue's type before it writes the Design:
- `z-nile/skills/z-design/checklists/feature.md`
- `z-nile/skills/z-design/checklists/defect.md`
- `z-nile/skills/z-design/checklists/chore.md`

## The flow
One type per raft: feature (`f`), defect (`d`) or chore (`c`). CI and test fixes are chores. A lone issue still gets a raft.
1. **z-ticket**, in `capture-<slug>`: the issue lands on `main` with `design: draft` and status `new`. No PR.
2. **z-design**, in `prep-<slug>`: `status <id> preparing` claims one issue; its design, checks and specs are written and reviewed; then `design: ready`, status `prepared`, and its design PR merges. It has no raft yet.
3. **z-raft**, in `raft-<slug>`: `./zn raft-plan` groups the prepared issues (or the arguments say which), each raft is claimed (its status only) and its members' `raft:` lines are written; the raft's own design and, for several issues, a coherence review; then the rafting PR merges.
4. **z-ready**, from the main checkout: the raft and its issues move to `active/`, and the prompt is written (ignored by git).
5. **z-run**: `/z-run R0010` in a session started in the main checkout reads the prompt, enters `.worktree/R0010` and hands off to zz-execute: `start` opens a draft PR; experiments, tests, the change, a clean code review; `done` promotes the specs, moves the items to `done/` and marks the PR ready; the PR merges when the gate and CI are green.
6. **z-stop**, from the main checkout: an `active` raft goes back to `prepared` and its prompt is deleted. The PR stays open.

`design:` is separate from status: z-design changes an issue's and z-raft a raft's, `draft` → `reviewed` → `ready`.

```mermaid
stateDiagram-v2
  direction LR
  [*] --> new: z-ticket
  new --> preparing: z-design claims
  preparing --> new: release the claim
  preparing --> prepared: design ready
  prepared --> preparing: prep again
  prepared --> active: z-ready
  active --> prepared: z-stop
  active --> done: z-run and zz-execute, done, merge
  done --> [*]
```

## Where the work lives
The main checkout stays on `main`; every edit is made under `.worktree/` (zz-rules skill, Worktrees).

| work | worktree |
|---|---|
| capture | `capture-<slug>` |
| prep | `prep-<slug>` |
| rafting | `raft-<slug>` |
| execution | `R0010`, branch `R0010-<slug>`, one PR |
| a skill, doc or config edit | `<area>-<slug>` |
