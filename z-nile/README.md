# z-nile

```mermaid
flowchart LR
  subgraph skills["skills: z-nile/skills, project/skills"]
    direction LR
    zticket["z-ticket"] --> zdesign["z-design"] --> zraft["z-raft (c0116, planned)"] --> zready["z-ready"] --> zrun["z-run"]
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

z-nile is the tooling that tracks, designs, gates and delivers the work of every project in this repository. A game is a project: pickman is one, in `pickman/`. z-nile belongs to no game.

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
| `z-design` | 2 | designs issues to `design: ready`: Design, `check.sh`, acceptance specs, experiments, the adversarial design review. Until c0116 it also forms the raft |
| `z-raft` | 3 | (c0116, planned) groups prepared issues into rafts |
| `z-ready` | 4 | from the main checkout: claims a prepared raft, moves it to `active/`, writes its `prompt.md` |
| `z-run` | 5 | launches a readied raft from the main checkout (`/z-run R0010`): reads its prompt, enters its worktree, hands off to zz-execute |
| `z-stop` | any | gives a readied or started raft back; its branch and PR stay |
| `zz-execute` | from z-run | the execution protocol: one branch, one PR, experiments, tests first, review, done, merge |
| `zz-review` | from z-design and zz-execute | the clean adversarial reviewer: design, stream and code modes |
| `zz-rules` | every step | the tracker's rules: ids, roots, lifecycle, worktrees, landing, spend |
| `zz-arch` | design and build of the tooling | the tooling's code structure |
| `zz-test` | every step | the gate, the spec runner, `check.sh`, sequestration and the guards |
| `zz-stats` | on demand | cost per issue and the rework rate |
| `pickman-arch`, `pickman-test` | pickman's design and build | pickman's code structure, and its game spec tiers |

## Design checklists
z-design reads the checklist for the issue's type before it writes the Design:
- `z-nile/skills/z-design/checklists/feature.md`
- `z-nile/skills/z-design/checklists/defect.md`
- `z-nile/skills/z-design/checklists/chore.md`

## The flow
One type per raft: feature (`f`), defect (`d`) or chore (`c`). CI and test fixes are chores. A lone issue still gets a raft (`--single`).
1. **z-ticket**, in `capture-<slug>`: the issue lands on `main` with `design: draft` and status `new`. No PR.
2. **z-design**, in `prep-<slug>`: `new raft` claims the issues (`preparing`); the designs, checks and specs are written and reviewed; then `design: ready`, status `prepared`, and the prep PR merges.
3. **z-ready**, from the main checkout: the raft and its issues move to `active/`, and the prompt is written (ignored by git).
4. **z-run**: `/z-run R0010` in a session started in the main checkout reads the prompt, enters `.worktree/R0010` and hands off to zz-execute: `start` opens a draft PR; experiments, tests, the change, a clean code review; `done` promotes the specs, moves the items to `done/` and marks the PR ready; the PR merges when the gate and CI are green.
5. **z-stop**, from the main checkout: an `active` raft goes back to `prepared` and its prompt is deleted. The PR stays open.

`design:` is separate from status, and only z-design changes it: `draft` → `reviewed` → `ready`.

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
| execution | `R0010`, branch `R0010-<slug>`, one PR |
| a skill, doc or config edit | `<area>-<slug>` |
