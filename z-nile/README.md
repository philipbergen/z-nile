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
  models[".models.toml (c0117, planned)"]
  dispatcher["dispatcher (c0117, planned)"]
  board["board: ./zn board (new board c0118, planned)"]
  skills <--> tracker
  models --> dispatcher
  dispatcher -->|"runs a skill on an item"| skills
  tracker --> board
  board -->|"copies the next command"| skills
```

z-nile is the tooling that tracks, designs, gates and delivers the work of every project in this repository. A game is a project: pickman is one, in `pickman/`. The arcade adds five more (c0183): the shared library `arcade`, the start place `portal`, and the games `snake`, `invaders` and `asteroids`, each in its own folder. z-nile belongs to no game.

## The five parts
- **The tracker.** `./zn` at the repository root runs the engine in `z-nile/engine/`. Each project keeps its issues and rafts in its own root, `<project>/.tracker/` (z-nile's in `z-nile/.tracker/`), listed in `z-nile/projects.toml`. One counter, `z-nile/next`, numbers every project. The rules are in the zz-rules skill.
- **The skills.** z-nile's skills live in `z-nile/skills/`, and a project's own in `<project>/skills/`. `.claude/skills/<name>` is a committed relative link to each, written by `./zn skills` and checked by `./zn skills --check` in the gate. The `z-` skills are the pipeline, in the order above; the `zz-` skills are called only from inside a step. Both prefixes are z-nile's: a project's skills are named `<project>-…`.
- **The dispatcher** (c0117, planned). It will run a step's skill on an item with the model `.models.toml` names, through that model's CLI, and record the spend.
- **`.models.toml`** (c0117, planned). It will say which model runs each skill, stacking from the repository root down to the work, as `.gitignore` does.
- **The board.** `./zn board` writes the whole tracker as one page (`.cache/board.html`), with the next command for each row. c0118 (planned) draws it again, with a tab per project.

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
- `default.project.json`, and any other `*.project.json`: the places the home builds. Every `$path` is a folder of the home, but for the library's two (`../arcade/src/shared` and `../arcade/src/server`), which the default place maps as `ReplicatedStorage.Arcade` and `ServerStorage.Arcade` in every home (c0185).
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
