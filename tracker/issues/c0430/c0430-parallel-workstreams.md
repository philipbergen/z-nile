---
id: c0430
type: chore
title: Parallel workstreams
slug: parallel-workstreams
raft: R0020
depends_on: [c0041, c0420]
emergent: false
design: draft
created: 2026-09-30
---

# c0430: Parallel workstreams

## Problem
A raft's issues are implemented one after another by a single agent on a single model, then reviewed once at the end by Opus. For a raft with several independent issues that is slow, and it spends the strongest model on routine implementation. R0040 (four issues, about 1,300 lines) took the lead agent through every step serially.

The user's goal (2026-09-30): implement a raft's functionality in **parallel workstreams on Sonnet**; review **each stream with a clean Sonnet subagent** when it finishes; once every stream is done, **evaluate the acceptance criteria**, make last-minute changes, and only then run the review of the **sum total with Opus**.

## Non-goals
- **Replacing the Opus review.** The stream reviews are a cheap first filter. Phase 4 of execute-raft (the adversarial review of the whole raft, on Opus) is unchanged and still required before `done`.
- **Parallelism inside one issue.** A stream is one issue. Splitting an issue across agents is out of scope.
- **Automatic agent orchestration in the tracker CLI.** The lead agent (the one following the prompt) spawns the subagents with its own tools; the CLI only plans and prepares.
- **Changing what `done`, `metrics` or spend attribution count.** Stream reviews are not review rounds, and spend is still recorded per issue by the lead.
- **Executing R0020 itself this way.** The tooling doesn't exist until this raft merges.

## Solution
- **A plan**: `tracker.sh workstreams <R-id>` (read-only) groups a raft's issues into **waves** from their `depends_on` and their **Touched modules**: issues in one wave don't depend on each other and don't share files, so they can run at the same time.
- **A workspace per stream**: `tracker.sh worktree ws-<issue> --from <raft branch>` (an extension of c0041's command) creates a named worktree whose branch starts at the raft branch's current tip.
- **A protocol** in `execute-raft` ("Phase 2B: parallel workstreams"): per wave, one Sonnet subagent per stream implements its issue tests-first in its worktree; when a stream reports done, a clean Sonnet subagent reviews just that stream; the lead squash-merges the stream into the raft branch; after the last wave the lead evaluates every issue's acceptance checks, makes last changes, and runs the existing Phase 3 and Phase 4 (Opus) unchanged.
- **The prompt** embeds the plan so the executor sees the choice without running anything first.
- **The other skills** (`review`, `tracker`, `make-prompt`) and the final report format learn the new mode.

## Design

### The plan: `tracker.sh workstreams <R-id>`
Read-only; it runs anywhere (it is on the main-checkout whitelist of c0041's worktree rule). `<R-id>` must be a raft.

- **Inputs, per member issue** (`store.members`, sorted by id):
  - `depends_on`: `store.idList(readFront(doc).depends_on)`, **restricted to the raft's members** (a dependency on an item outside the raft, for example one already merged, is ignored);
  - **Touched modules**: the backticked paths on the bulleted lines of the issue's `### Touched modules` section (up to the next `##` heading), with a trailing `/` removed. Comment lines and prose are ignored. An issue with no such bullets has *no touched modules*.
- **Overlap**: two paths overlap iff they are equal or one is a parent directory of the other (`a` and `a/b`, compared by whole path components). An issue with no touched modules overlaps **every** other issue (the plan can't prove it independent).
- **Waves**: deterministic. Repeat: take the lowest-id unassigned issue whose in-raft dependencies are all assigned; its `after` set is its dependencies plus every already-assigned issue whose touched modules overlap its own; its wave is `1 + max(wave of the after set)`, or 1 if the set is empty. No ready issue but some unassigned (a cycle) → fail `dependency cycle among: <ids>`.
- **Output** (stdout), exactly:
  ```
  raft R0010: 4 issues
  f0010 wave 1
  f0020 wave 1
  f0030 wave 2 after f0010 (overlap)
  f0040 wave 2 after f0020 (depends_on)
  parallel: yes (wave 1: f0010 f0020)
  ```
  - the header reads `raft <id>: <n> issue` for one issue and `<n> issues` otherwise; then one line per issue, sorted by id; `after` lists its after-set sorted by id, each as `<id> (<reason>)` joined by `, `, where the reason is `depends_on` if the issue is in its `depends_on`, else `no touched modules` if either issue has none, else `overlap`;
  - the last line is `parallel: yes (wave <k>: <ids>)` for the lowest wave with two or more issues, else `parallel: no`.
  - an issue with no touched modules also prints `warning: <id> has no Touched modules; serialized` to stderr.
- **Shared by `prompt`**: one function builds the plan text; `workstreams` prints it and `prompt` embeds it.

### `tracker.sh worktree <name> --from <ref>` (extends c0041)
- Valid only with a **named** target (`ws-c0420` and the like); with a raft id it fails `--from is for named worktrees`.
- `<ref>` must resolve (`git rev-parse --verify --quiet <ref>^{commit}`), else `unknown ref <ref>`, creating nothing.
- For a new branch the base is `<ref>` instead of `origin/main` (still with `--no-track`). An existing or checked-out branch is handled exactly as in c0041 (resume, refuse).
- Stream worktrees are named `ws-<issue id>`, for example `ws-c0420`; branch `ws-c0420`.

### The protocol (written into `.claude/skills/execute-raft/SKILL.md`, "Phase 2B")
Use it when `tracker.sh workstreams <R-id>` ends with `parallel: yes` and the human hasn't asked for sequential execution. Otherwise Phase 2 runs as today (Phase 2A). The **lead** is the agent following the prompt; it alone pushes, merges, comments on the PR and runs `tracker.sh commit`/`done`.

1. **Plan**: run `workstreams`, post it as a PR comment, and execute wave by wave.
2. **Start a wave**: for every issue in the wave, create its worktree with `scripts/tracker.sh worktree ws-<issue> --from <raft branch>`, then spawn one **Sonnet** subagent per stream (Agent tool, `model: "sonnet"`), **all in one message so they run concurrently**. The brief contains: the raft and issue ids; the absolute stream worktree path ("your shell doesn't keep a working directory: start every command with `cd <path> &&` or use `git -C <path>`"); the issue document, `check.sh` and acceptance specs to satisfy (paths, all sequestered); the rules: tests first, implement the Design exactly, edit only the issue's Touched modules and its own Verification log, never edit `check.sh`, acceptance specs or `tracker/architecture.md`, never push, comment on the PR or run `tracker.sh commit`; commit with plain `git add -A && git commit -m "<issue>: <what>"`; run `scripts/check.sh --affected` and `scripts/tracker.sh check <issue>` in the worktree; stop and report (don't improvise) on the protocol's stop conditions. The stream reports `done` or `blocked`, its final commit sha, minutes worked, deviations, and anything another issue needs.
3. **Review each stream** as soon as it reports `done`: a clean **Sonnet** subagent (`model: "sonnet"`) with the `review` skill in **stream mode**: inputs are `git diff <raft branch>...ws-<issue>`, the issue document, `check.sh` and acceptance specs, and read access; it runs the stream's checks; it writes only `tracker/rafts/active/<R-id>/stream-review-<issue>-NNN.md` **in the stream worktree**, in the review skill's format (no Judged section). The lead commits that file on the stream branch. The stream's author (continue the same subagent with SendMessage) answers in `stream-refute-<issue>-NNN.md` with `fixed` or `refuted` lines, as in Phase 4. **At most 2 rounds per stream**; a round-2 high finding still standing means the lead takes that issue over or escalates.
4. **Merge the stream**: in the raft worktree, `git merge --squash ws-<issue>`, then `scripts/tracker.sh commit -m "<issue>: <what the stream did>" --issue <issue> --time <stream minutes>`. Squashing stages exactly the stream's net change, so spend lines are attributed to the issue; the stream's own commits stay out of the raft history. Run `tracker.sh check <issue>`. Then remove the stream worktree and branch (`git -C <root> worktree remove <path> && git -C <root> branch -D ws-<issue>`). The lead posts a PR comment for the stream: review verdict and findings by severity, the merge sha.
5. **Next wave**: its streams start from the raft branch after the previous wave's merges. A blocked or unresolved stream is finished by the lead itself in the raft worktree (Phase 2A for that issue), and the Verification log says so.
6. **Integrate**: after the last wave, **evaluate the acceptance criteria**: `scripts/tracker.sh check <issue>` for every member issue and the raft's `check.sh`. The lead makes any last-minute changes (small, committed with `tracker.sh commit`, each noted in the affected issue's Verification log). Then Phase 3 (whole-raft verification) and **Phase 4, the adversarial review of the sum total, on Opus**, exactly as today.
7. **Model policy**: stream implementers and stream reviewers run on Sonnet by the user's decision; the Phase 4 reviewer still runs on **Opus** (`model: "opus"`). Stream reviews never substitute for it, are not review rounds (`tracker.sh done` and `metrics` ignore `stream-review-*` and `stream-refute-*` files), and their findings need no `refute` answers for `done`.
8. **Final report** gains one line: `Workstreams: <issue>: <stream review verdict> | sequential`.

### Other documents
- **`.claude/skills/review/SKILL.md`**: a short "Stream mode" section: scope is one issue's diff, the file name, no Judged criteria, Sonnet is allowed, and it never replaces the Opus review.
- **`.claude/skills/tracker/SKILL.md`**: `workstreams` and `worktree <name> --from <ref>` in the command table; the PR-record paragraph adds the per-stream comments.
- **`.claude/skills/make-prompt/SKILL.md`**: the report (step 4) adds the plan's last line (`parallel: yes|no`).
- **`tracker/templates/prompt.md`**: a `## Workstreams plan` section with `{{WORKSTREAMS}}` and one sentence: "If it says `parallel: yes`, follow execute-raft Phase 2B unless the human told you to run sequentially."
- **`tracker/architecture.md`**: unchanged.

### `scripts/tracker/main.luau` changes
- `touchedModules(item)`, `workstreamPlan(raft): (string, string)` (text and the warnings), `cmd.workstreams`, the `--from` option in `cmd.worktree`, the `{{WORKSTREAMS}}` variable in `cmd.prompt`, USAGE.
- `reviewProblem` and `metrics` already match `review-NNN.md` with anchored patterns; a spec pins that stream files don't match.

### Scalability
- The plan reads one document per issue: O(issues²) overlap comparisons on a handful of issues.
- Real cost is agent spend: N Sonnet implementers and N Sonnet reviewers plus the Opus review. The plan's `parallel: no` default keeps single-stream rafts on the old path.

### Maintainability
- The protocol lives in one skill section; the tooling is two small, deterministic, tested functions.
- The wave rule is data (`depends_on`, Touched modules), so well-written issues are the only input.

### Usability
- The human sees the plan in the prompt, the per-stream PR comments as they happen, and one Opus review at the end, as today.
- Agents get exact briefs to copy and a fallback (sequential) when a stream blocks.

### Touched modules
- `scripts/tracker/main.luau`
- `tracker/templates/prompt.md`
- `.claude/skills/execute-raft/SKILL.md`
- `.claude/skills/review/SKILL.md`
- `.claude/skills/tracker/SKILL.md`
- `.claude/skills/make-prompt/SKILL.md`

### Affected specs
`lune run scripts/affected -- scripts/tracker/main.luau tracker/templates/prompt.md` prints `ALL`, because `scripts/` forces a full run. New: `acceptance/workstreams.spec.luau`.

## Unknowns & experiments
- **E1 (prototype)**: can the planned tooling satisfy the sequestered spec, and does the spec catch wrong implementations? Recorded in the Verification log (prototype on top of c0420 and c0041's prototypes, reverted).
- **E2 (run in prep: PASS)**: `done`'s and `metrics`' review matching is anchored (`^review%-(%d+)%.md$`, `^design%-review%-%d+%.md$`), read in `scripts/tracker/main.luau`; the spec pins it.
- **E3 (Observed, OC1)**: whether Sonnet subagents in separate worktrees deliver a real raft end to end can only be judged by running one. It doesn't block the merge; the first raft run this way is the test.
- **E4**: can a lead spawn many subagents in one message and continue a finished one with SendMessage? The Agent tool documents both (`SendMessage` continues an agent by id); the protocol names them as the mechanism and falls back to sequential if a harness lacks them.

## Regression guard
- **`done`, `metrics`, `prompt`, `worktree`** behaviour is unchanged when no stream files exist, no `--from` is given and the raft has one issue: the existing specs (c0010 lifecycle, `tests/tooling/*`, c0041's worktree spec) stay green; the prompt gains only a plan section.
- **R0040-style rafts** (several issues) now show `parallel: yes`, but nothing changes unless the lead chooses Phase 2B.

## Test plan
`acceptance/workstreams.spec.luau` builds a scratch `.cache/ws-e2e/` like c0041's: a seed clone of the repo (no origin, `main` forced, the working tree's `scripts/`, `tracker/templates/`, `.gitignore` overlaid, tracker emptied) in which it creates issues and rafts with `new` and edits their `depends_on` and Touched modules; then a bare `origin.git` cloned from the seed and a clone `main/` for the worktree cases. Rafts: `R0010` (`demo`): f0010 (`src/a`), f0020 (`src/b`), f0030 (`src/a/sub`), f0040 (depends on f0020, `src/c`); `R0020` (`solo`): f0050; `R0030` (`chain`): f0060 (no touched modules), f0070 (`src/z`), f0080 (depends on f0070 and on `c0999`, which isn't in the raft; `src/y`); `R0040` (`loop`): f0090 and f0100 depending on each other.

Cases (`spec case → AC`):
- `workstreams orders waves by depends_on and serializes overlapping modules` → AC1 (R0010, exact output)
- `a single-issue raft is sequential` → AC1
- `an issue without touched modules is serialized with a warning` → AC1 (R0030, exact output, also a dependency outside the raft is ignored)
- `a dependency cycle and an unknown raft are errors` → AC1
- `worktree --from bases the new worktree on the ref` → AC2
- `worktree --from rejects an unknown ref and a raft id` → AC2
- `stream review files are not review rounds` → AC3 (an active raft with only `stream-review-*` and `stream-refute-*` files: `done` still says `no review-NNN.md`, and `metrics` counts zero code rounds)
- `prompt embeds the workstreams plan` → AC4

### Rules and mutants
`run` rows were mutation-tested on the prep prototype (Verification log); `reasoned` rows were not run.

| rule | spec :: case | mutant it kills | checked |
|---|---|---|---|
| Dependencies put an issue in a later wave | `workstreams orders waves …` | ignore `depends_on` | run |
| Overlapping touched modules (equal or parent/child) are serialized | `workstreams orders waves …` | compare only equal paths; ignore overlap | run |
| An issue with no touched modules is serialized after everything and warns | `an issue without touched modules …` | treat it as independent | run |
| Dependencies outside the raft are ignored | `an issue without touched modules …` (f0080 depends on `c0999`) | fail or wait on an unknown dependency | run |
| A cycle is an error naming the issues; an unknown raft is an error | `a dependency cycle and an unknown raft …` | loop forever; print an empty plan | run |
| `parallel:` names the lowest wave with two or more streams, else `no` | `workstreams orders waves …`, `a single-issue raft …` | always `yes`; report the last wave | run |
| `--from` bases a new worktree on the ref | `worktree --from bases …` | ignore `--from` (use `origin/main`) | run |
| `--from` needs a resolvable ref and a named target | `worktree --from rejects …` | fall back to `HEAD`; accept a raft id | run |
| Stream files are not review rounds | `stream review files are not review rounds` | match any file containing `review` | run |
| The prompt embeds the plan | `prompt embeds the workstreams plan` | omit the section | run |
| execute-raft carries the protocol; model policy stated; other docs updated | AC5 grep and JC1 | leave a step out; put Sonnet on the Phase 4 review | reasoned (greps and a ruling, not a mutation) |

## Acceptance criteria

### Checked
- **AC1**: `tracker.sh workstreams <R-id>` prints the plan in the documented format: waves from `depends_on` (in-raft only) and overlapping Touched modules, issues with no touched modules serialized with a warning, `parallel: yes|no`, and fails on a dependency cycle or an unknown raft.
- **AC2**: `tracker.sh worktree <name> --from <ref>` creates the worktree on a new branch at `<ref>`'s tip (not `origin/main`), is idempotent, and rejects an unknown ref and a raft id, creating nothing.
- **AC3**: `stream-review-*` and `stream-refute-*` files in a raft directory are not review rounds: `done` still requires `review-NNN.md`, and `metrics` doesn't count them.
- **AC4**: `tracker.sh prompt` embeds the plan under `## Workstreams plan`.
- **AC5**: The execute-raft skill contains the parallel protocol (Phase 2B with the plan, the per-stream Sonnet implementer and Sonnet review, the squash merge, the acceptance evaluation, and the Opus review of the whole), the review skill has a stream mode, the tracker skill lists the two commands, and the prompt template has the plan section (the greps in `check.sh`).

### Judged
- **JC1: the protocol is complete, ordered and safe.**
  - **Pass**: a reader who has never seen the repo can follow Phase 2B from the skill alone. It states, in this order: plan; start a wave (Sonnet streams, one message, the brief's contents); review each stream (clean Sonnet subagent, stream files, at most 2 rounds); squash-merge with `tracker.sh commit --issue`; next wave; evaluate every issue's acceptance checks and the raft check; last-minute changes; Phase 3; Phase 4 on Opus. It says that only the lead pushes, merges, comments on the PR and runs `tracker.sh commit`/`done`, that streams never touch files outside their Touched modules or any sequestered file, what happens when a stream blocks, and that stream reviews never replace the Opus review.
  - **Fail**: a missing or contradictory step, Sonnet put on the Phase 4 review, a stream allowed to push or merge, or no fallback. Quote it.

### Observed
- **OC1** (after the first raft executed this way): the PR shows the plan comment, one comment per stream with its review verdict, the merge shas, and the Opus review of the whole; the final report lists `Workstreams:` per issue. Note anything that felt wrong (briefs too thin, merge conflicts, review noise) for a follow-up.

## Implementation steps
1. `touchedModules`, `workstreamPlan` and `cmd.workstreams`, plus USAGE. Run AC1. Commit.
2. `--from` in `cmd.worktree`. Run AC2. Commit.
3. `{{WORKSTREAMS}}` in `cmd.prompt` and the template. Run AC3 and AC4. Commit.
4. Docs: execute-raft Phase 2B and the final report line, the review skill's stream mode, the tracker and make-prompt skills. Run AC5. Commit.
5. `scripts/tracker.sh check c0430`, `scripts/check.sh --full`, `promote-check R0020`. Commit.

## Verification log

- **Prototype run (2026-09-30), reverted, never committed:** the c0430 tooling (about 150 lines: `touchedModules`, the plan, `cmd.workstreams`, `--from`, the prompt section and template) stacked on the prototypes of c0420 and c0041.
  - All 8 workstreams-spec cases pass, `scripts/check.sh --full` passes with all three prototypes and the repo migrated (346 specs), and `tracker.sh check c0430` passes 5 of 6, the exception being AC5 (the skill text, which the executor writes).
  - Thirteen planted mistakes each fail the case written for them: ignoring `depends_on`; overlap only for equal paths; never overlapping; no-touched-modules counted as independent; waiting on a dependency outside the raft; a cycle printing a partial plan; `parallel:` always yes; reporting the last wave rather than the lowest; ignoring `--from`; an unknown ref falling back to `HEAD` (git's own error for a bad ref already names it, so only this mutant proves the rule); accepting `--from` with a raft id; counting stream files as review rounds; omitting the plan from the prompt.

