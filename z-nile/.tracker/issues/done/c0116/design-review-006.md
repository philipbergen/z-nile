# Review 006: c0116 (design mode)
Inputs: prep-c0116 at f53513fb (the rebase onto c0115's final design 5308d42f: `c0116.md` §3, the new M93 row and the Verification log, `check.sh`, every acceptance spec's delta); prototype `.worktree/proto-c0116` at c02954ad (on simulation 689e29b9, on `proto-c0115` 77298f1e), with `cmd["raft-plan"]`, `cmd.new` (raft), `projectRoot`, `projects.projectOf`, `store.roots`, `z-nile/lib/ac.sh`, the skills' `new raft` lines and c0114/classified's retired/ override read. The prep's `check.sh` and `acceptance/` are byte-identical to the prototype's. `./zn lessons --when design --full`; `./zn capture c0116`. Every run was in a scratch clone of the prototype with its origin removed (`scratchpad/c0116-review006/clone`), fixtures under its own `z-nile/.cache`. Scope: the rebase delta, as approved in round 5.
Dropped from review-005: none open (F1 answered in round 5).

Reproductions rerun on the new prototype (rounds 3–5's specs, ported mechanically to `pickman/.tracker` and `--project pickman`: `scratchpad/c0116-review006/rv{3,4,5}.spec.luau`):
- rv3: T1 (a `check.sh` redesign inside the window) refused; T2 (unfold, fold, old review) refused "predates its record"; T4 (forged and empty `grouped:`) refused; T6 (empty raft) named by audit, refused by `ready`. 5/5.
- rv4: Q1 refused after an acceptance file is removed, then passes after a refold and a new review; `ready` with an ignored `.DS_Store` in the main checkout succeeds. The spec's next line fails only because `ready` moved the folder to `active/`, as in round 5. Q2, Q3 (cross-member path through stop and ready, now `pickman/.tracker/issues/active/c0060`) and Q4 (compact, remap, carried move, `ready`) all hold.
- rv5: control and Q5 (renumber with an untracked work file) both leave `ready` succeeding. 3/3.

Project inference (new `scratchpad/c0116-review006/rv6.spec.luau`, a rafting worktree at the checkout's top):
- `new raft … c0010 --project z-nile` with c0010 in pickman is refused ("the raft is made in z-nile/.tracker: c0010 is in pickman/.tracker"). Members of two projects are refused ("a raft holds issues of one project"). So is `fold R0030 c0020` across projects.
- No `--project` at the top is refused ("no project holds the checkout's root"). So is a root name passed as `--project`.
- `raft-plan` prints `./zn fold R0030 c0010 c0011` and `./zn new raft chore c0020 c0020 --project z-nile`. `--apply` runs both from the top, and c0020 gets R0040 in `z-nile/.tracker`.
- An issue under an unregistered `other/.tracker` is invisible to `raft-plan` (`store.roots` is the registry's). That is c0115's rule ("a directory not listed is not a project"), not a c0116 gap.

Held (no finding):
- The port is mechanical. The spec deltas are paths, `--project pickman`, fixtures in the home's `.cache`, reads from `TOP`, and retired's nested run through `process.exec` with `cwd = {work}/z-nile`. The only behaviour change is M93, and the plan-cli EXPECTED pins both project names, so a wrong name would be seen.
- `check.sh` AC8 uses `"$ZN_ROOT/zn"`, exported by `ac.sh` before it changes to the home.
- c0114/classified's override reads `projects.load(TOP)`, which takes a directory.
- Every `./zn new raft` in the skills, README and AGENTS.md carries `--project` (grep: none without).
- Scope: the rebase changed no Problem, Solution or AC outcome text. `./zn capture c0116` prints "capture: no history for c0116 on origin/main": real origin/main holds it at `tracker/issues/c0116`, and this branch's engine looks under the new roots. This is not a confirmed capture. Judged from fb7fd80 instead, as rounds 3–5 did, the scope is unchanged. Following a capture across the root move is c0115's concern.
- Lessons: no new defect against the design checks. "Every argument pinned" holds for `--project`.
- Gate on the clone: pickman 1160/0. z-nile 1080 passed, 1 failed: c0120/finished on five literals in `done/c0115/check.sh`. That is c0115's known failure and is not counted against c0116. `./zn check c0116`: 10/10.

### F1 [low] raft-plan's fallback for a root with no project prints `--project <root>`, a command `new raft` always refuses
Where: `cmd["raft-plan"]`, `table.insert(args, if project then project.name else op.root)`.
Evidence: `store.roots()` is the registry's, so `projectOf` cannot return nil today and the branch never runs. If it did, the printed line would be `./zn new raft … --project pickman/.tracker`. rv6 D shows that line refused ("--project pickman/.tracker: not a project"), and under `--apply` it would fail after the earlier commands had already run.
Recommendation: `fail` at plan time ("<root> is no project's root in z-nile/projects.toml"), before printing or running anything. Or keep the line and add a comment saying it can't be reached. No spec case is needed.

Verdict: approve
