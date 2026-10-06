# Review 001: R0025 (design mode)
Inputs: 3782e0c (prep-ready-raft, synced to origin/main eb2ba87); R0025.md, R0025/check.sh; c0067, c0068, c0069, c0070 (documents, check.sh, acceptance specs); scripts/tracker/{main,publish,store}.luau, scripts/tracker.sh; promoted specs in tests/acceptance; done check.sh files.

### F1 [high] Five sequestered case-name checks can never pass, because stylua wrapped those `it(` calls over two lines
Where: tracker/issues/c0067/check.sh:20 (`cases_pass`), c0068/check.sh:20, c0069/check.sh:19; ready.spec.luau:279-280 and :401-402, stop.spec.luau (the "stop moves a readied raft back" and "stop removes prompt.md" cases), prompt.spec.luau ("prompt prints the readied raft's prompt.md exactly").
Evidence: `cases_pass` requires `grep -qF "it(\"$c" "$spec"`. Run against the specs as written:
```
MISS ready moves the raft and its members        (c0067 AC4)
MISS start on a readied raft                      (c0067 AC7)
MISS stop moves a readied raft back               (c0068 AC2)
MISS stop removes prompt.md                       (c0068 AC3)
MISS prompt prints the readied raft's prompt.md exactly   (c0069 AC2)
```
Each case exists, but as `it(\n\t\t"<name>",`: stylua breaks a call whose first argument is a long string. So c0067 AC4/AC7, c0068 AC2/AC3 and c0069 AC2 fail even with a perfect implementation. RC0 fails too, and the executor can't fix it, because the files are sequestered.
Critique: the easy fix is to shorten the five names until they fit on one line. stylua's width then decides whether a check works, and the next rename brings the bug back.
Consequences: a check that matches the quoted name alone (`"\"$c"`) could also match a string elsewhere in the spec. The names are long and specific, so that risk is small, but the match should still be anchored to a case.
Recommendation: in all four member check.sh files, make `cases_pass` whitespace-tolerant, for example `tr -d '\n\t' < "$spec" | grep -qF "it(\"$c"`, which joins `it(` and the name. Then rerun the five-name grep above to prove every label resolves. Add a prep step to ticket-prep's "Verify the wiring": run each `cases_pass` name lookup by itself, because a failing spec hides this bug before implementation.

### F2 [high] After a readied raft's PR merges, the main checkout keeps `tracker/rafts/active/<R>/prompt.md`, and every store-walking command there fails with "duplicate id"
Where: c0067 Design (promptPath, E1); c0068 step 3 (only `stop` cleans up); c0070 refreshBoard and sync; scripts/tracker/store.luau:64-75 and :99-113.
Evidence: E1 (run in prep) shows that a pull which moves `tracker/rafts/active/R` away leaves the ignored `prompt.md`, and its directory, behind. The normal end of a raft is exactly that pull: `done` moves `active/R → done/R` on the branch, the PR merges, and Landing step 4 runs `<root>/scripts/tracker.sh sync`. The main checkout then holds both `tracker/rafts/active/R/` (only `prompt.md`) and `tracker/rafts/done/R/`. `store.find` collects both directories and errors `duplicate id R: …` (store.luau:73-75), and `store.all("raft")` calls it for every raft. So in the main checkout:
- `tracker.sh list` and `board` fail, and with them every refresh in c0070, which only warns, so it fails quietly;
- so do `metrics` and `new raft`.

The same happens after a `stop` run from another clone, and with a Finder `.DS_Store` (ignored globally) in the directory, which also defeats c0068's "remove the directory if it is empty". c0068's own spec only covers a `stop` from the same checkout.
Critique: the tempting fix is "`done` deletes prompt.md". But `done` runs in the raft worktree, which has no prompt.md. The file lives only in the main checkout.
Consequences: a cleanup step in the main checkout must never delete the prompt of a raft that is still readied. It must also run after every pull there (ready, stop, sync, the c0070 fast-forward), or one path will miss it.
Recommendation: add `sweepPrompts()` to c0067, run in the main checkout after each of its pulls (ready, stop, `sync`, and c0070's refreshBoard fast-forward). For each `tracker/rafts/active/<dir>` whose `<dir>.md` is not tracked at HEAD, remove the ignored files (`git clean -fdX -- tracker/rafts/active/<dir>`), then the directory. Spec cases (ready.spec or a new c0067 case):
- ready R0001; from another clone, push the `active/R0001 → done/R0001` move to origin; run `sync` in the main clone. Then `prompt.md` and `active/R0001` are gone, and `list` and `board -O` succeed.
- With a `.DS_Store` placed in `active/R0001` before the move, the same holds.
- A still-readied raft's prompt.md survives the sweep.

Also add a c0069 case: a prompt.md left behind for a raft that is no longer readied is refused. This finally kills its own "reads any file that exists" mutant (see F10).

### F3 [high] c0069 turns two promoted c0045 specs red, and its Overrides line does not name them
Where: tests/acceptance/c0045/workstreams.spec.luau:351-364; tracker/issues/done/c0045/check.sh:34-35 (AC4); c0069 Regression guard / Overrides.
Evidence: two cases run against the fixture's `main` clone, which has a bare origin (spec lines 208-209):
- "prompt embeds the error for a plan that can't be built" runs `tr(main, { "prompt", "R0004", "--stdout" })`;
- "prompt embeds the workstreams plan" runs `tr(main, { "prompt", "R0001", "--stdout" })`.

After c0069, `prompt` is a reader. It fails unless the raft is in `active/` on origin/main and prompt.md exists (c0069 Design step 2-3), and `--stdout` is gone. Both cases fail, so RC0's `scripts/check.sh --full` fails, and so does c0045's AC4. c0069's Overrides names only c0046's launch.spec, c0046's check.sh and c0005's worktree case. c0067's Overrides names c0045's check.sh only for its `parallel:` grep.
Critique: the tempting fix is to delete the two cases. That drops the only pin on "the prompt embeds the plan, or the plan's error", which `renderPrompt` keeps.
Consequences: the plan-in-prompt behaviour needs a new pin. Getting it through `ready` needs a prepared raft on an origin, which c0045's fixture doesn't have.
Recommendation:
- Add both cases to c0069's Overrides, removed from c0045's spec, and drop AC4's `cases_pass` line from c0045's check.sh (see F5 for when to edit it).
- Move the pins to c0067's ready.spec: a case asserting that `prompt.md` contains `## Workstreams plan` and the plan's `parallel:` line, plus a raft with an internal `depends_on` cycle whose readied prompt.md contains `plan unavailable: dependency cycle` and `parallel: no`.
- Add the matching Test plan and Rules and mutants rows.

### F4 [high] Narrowing c0005's worktree spec breaks c0053's check.sh AC8, which byte-compares that spec against a frozen copy
Where: tracker/issues/done/c0053/check.sh:65-73 (AC8, `replacements_applied`); tracker/issues/done/c0053/replacements/c0005-worktree.spec.luau; c0069 Overrides (the c0005 case).
Evidence: AC8 runs `cmp -s "$R/c0005-worktree.spec.luau" tests/acceptance/c0005/worktree.spec.luau`. Today the two are identical (checked with `cmp`). c0069 deliberately edits `tests/acceptance/c0005/worktree.spec.luau` ("prompt does not create a placeholder raft…"), so `tracker.sh check c0053` fails afterwards. Neither issue names it. No R0025 check runs c0053's check.sh, so the break would land unnoticed.
Critique: the tempting fix is to also edit c0053's check.sh to drop AC8. That loses the pin on c0053's prepared replacements, and it is one more sequestered edit.
Consequences: the frozen copy has to follow the spec edit exactly, or AC8 stays red.
Recommendation: add `tracker/issues/done/c0053/replacements/c0005-worktree.spec.luau` to c0069's Overrides and Touched modules. It is rewritten to be byte-identical to the narrowed spec, which keeps AC8 as it is. Add a c0069 check: `cmp -s tracker/issues/done/c0053/replacements/c0005-worktree.spec.luau tests/acceptance/c0005/worktree.spec.luau`. Also see F9 for running the overridden done check.sh files.

### F5 [high] The plan edits done items' `check.sh` files during execution, which the code-mode sequestration check rules a high finding and the prompt's hard rule 3 forbids
Where: c0067 Touched modules / Overrides (done check.sh of c0005, c0045, c0046, c0047, c0053); c0069 Overrides (c0046 check.sh AC1-AC4, AC6); review skill, Code mode item 2; tracker/templates/prompt.md hard rule 3.
Evidence:
- The code reviewer runs `git diff --find-renames=100% --name-status origin/main...HEAD -- 'tracker/**/check.sh' …`, which "must list nothing except `R100` renames. Any other change is **high**." The executor's edits show up there as `M tracker/issues/done/c0005/check.sh` and four more.
- The prompt the executor receives says: "**Never edit** any `check.sh` … If one of them is wrong, stop and escalate."
- So the executor is told to make edits that its own protocol forbids, and the Phase 4 review must flag them. The precedent (R0023 `5f7868f`, R0013 `aa06e7c`) made such edits in the **prep** PR.

Critique: the tempting fix is a note in the raft doc saying "these M lines are allowed". The reviewer's rule and the prompt's hard rule don't read the raft doc, so the conflict remains.
Consequences: making the edits in prep turns these done checks red on `main` until R0025 merges, because they name `ready-raft` before it exists. Nothing runs done check.sh files automatically: not the gate, not CI, and not R0025's RC0.
Recommendation: make every done `check.sh` edit (c0067's five `make-prompt → ready-raft`; c0069's c0046 AC1-AC4 removal, AC6 launch greps and label; c0045's AC4 per F3) in **this prep PR**. Remove them from both issues' Touched modules and Implementation steps. Then state in each Overrides line "done in prep: <file>". The promoted specs under `tests/acceptance/` (c0047, c0046, c0005, c0045) stay in execution: they are outside the `tracker/**` sequestration pattern and must stay green on main. c0067's AC11 and c0069's AC6 then verify the prep edits instead of requiring them.

### F6 [medium] Publish's move validation allows moves into and out of `done/`, lets a second change resurrect or overwrite a moved file, and has no spec for the one capability that deletes (`from`)
Where: c0067 Design, publish.luau "Move validation" 1-6; publish-move.spec.luau; scripts/tracker/publish.luau:157-176, :231-240.
Evidence:
- (a) Rule 1 only requires "different directories", so `tracker/issues/done/c0005 → tracker/issues/c0005` is a valid published move. ready and stop only ever move between the backlog and `active/`, and `done/` moves happen on branches.
- (b) Nothing refuses two changes with the same `path`, or a change whose `path` equals another change's `from`:
  - a non-move status edit of `tracker/issues/c0001/c0001.md` in the same publish as the c0001 move re-adds the source file. diff-tree accepts it, since both paths are "wanted", and rule 5 is satisfied, so `main` ends up with c0001 in two directories. `store.find` then errors "duplicate id" in every checkout.
  - a non-move *creation* at the move's target `tracker/issues/active/c0001/c0001.md` overrides the validated content in `makeTree`, because the last node wins.
- (c) Rule 6 counts every `from` as wanted, so rule 1 (`from` is an `itemPath`) is the only thing stopping `{ path = "tracker/issues/active/c0001/x", from = "src/x.luau" }` from deleting a source file on main. No case in publish-move.spec tries it, so the mutant "itemPath checked on `path` only" passes AC2.
- (d) The check.sh rule `normalize(new) == normalize(old)` also accepts changes to the state segment of ids that are not being moved.
- (e) The existing carriage-return refusal (publish.luau:165) applies to moved files too, so a moved spike output or binary with `\r` blocks `ready`. There is none in `tracker/` today.

Critique: the tempting fix is a single "no duplicate paths" check. That leaves (a), (c) and (d).
Consequences: restricting moves to backlog↔active keeps `done/` branch-only. A future published "undo done" would need a design decision.
Recommendation: add these to rules 1-6, each with a refusing case in publish-move.spec that checks origin's tip is unchanged:
- every `path` and every `from` is unique across the publish, and no change of any kind writes a path inside a moved source directory, or a moved target that is not its own move;
- neither side of a move is under `done/`;
- a `from` that is not an `itemPath` is refused, with a case using `from = "src/x.luau"` that asserts `src/x.luau` is still on origin;
- in a moved `check.sh`, only the moved ids' state segments may differ: compare `paths.rewrite(old, dirs)` to the new text, where `dirs` holds the publish's own moves;
- moved files are exempt from the `\r` rule, since they are byte-checked against origin.

### F7 [medium] AC8's "current raft by branch" case is passed by the mutant "the lowest-id active raft"
Where: c0067 ready.spec.luau:418-427 ("commit works on a raft branch…"), :442-452; Rules and mutants row "the current raft is found by branch".
Evidence: the commit case runs on R0001's branch, while R0004 is the other readied raft. A `currentRaft` that returns the first active raft in `store.all` order gives R0001 there too, and puts `spend.md` in R0001, as the case expects. The later `commit` on wt4 (R0004's branch) asserts nothing about attribution, and `done R0004` names its raft explicitly. So the listed mutant "exactly one active raft kept" is killed, but this equally plausible one is not.
Critique: the tempting fix is to swap the two rafts. That only moves the blind spot to the "highest id" mutant.
Consequences: none beyond one assertion.
Recommendation: in the done case, after `trOk(wt4, { "commit", … })`, assert that `tracker/rafts/active/R0004/spend.md` exists in wt4 and that `tracker/rafts/active/R0001/spend.md` does not exist in wt4. Add the mutant "first or lowest active raft" to the Rules and mutants row.

### F8 [medium] Promoted specs pin wording that this raft rewrites, and the Regression guards don't name them
Where: c0067 "Tracker skill" bullets (the start row, the board row, the claim wording); c0070 "Tracker skill" (the board row); c0068 (status refusal).
Evidence:
- tests/acceptance/c0050/start-depends.spec.luau:172-183: the `| start | ` row must contain `depends_on`, `done`, `origin/main`, `never edit`, `stop`. c0067 rewrites that row for a readied raft, where start checks no dependencies, so the natural new row drops them.
- tests/acceptance/c0053/commands.spec.luau:535-538: `status R0001 active` must fail with stderr containing `only tracker.sh start`. c0067 moves the claim to `ready`, so the obvious reword ("only tracker.sh ready claims active") breaks it. The USAGE status line (`start claims active`) invites the same edit.
- tests/acceptance/c0048/board-docs.spec.luau and c0057/open.spec.luau:119-130: the `| board | ` row must keep `board.yml`, `tracker-board`, `gh run download`, `rm -rf .cache/board-ci`, `-D .cache/board-ci`, `` `tracker.sh board [--out PATH] [-O]` `` and ``unless `-O` ``. Both c0067 and c0070 rewrite this row.
- tests/acceptance/c0047/override-check.spec.luau:84-85: it cuts the readiness section at `"3. "`, so ready-raft's step 3 must begin with `3. `.

RC0 catches each of these, but only after implementation. The executor then has to escalate or contort the docs.
Critique: listing them as Overrides would be wrong, because none of these behaviours needs to change.
Consequences: none: these are constraints to keep, not changes.
Recommendation: add each spec and its exact tokens to the Regression guard of the issue that edits that text (c0067: c0050, c0053 and c0047; c0067 and c0070: c0048 and c0057), with the instruction to keep them. For the status refusal, say that the message must keep the literal substring `only tracker.sh start`, for example "only tracker.sh start or tracker.sh ready claims active". For the start row, keep the five tokens by describing both paths, for example "a backlog raft (legacy): … depends_on … done … origin/main … never edit … stop".

### F9 [medium] The wording rule lists 4 of c0005's 13 banned phrases, and nothing in R0025 runs the done check.sh files it overrides
Where: R0025.md "Rules shared by the raft", Wording; c0067 AC10's phrase scan; tracker/issues/done/c0005/check.sh AC5.
Evidence:
- c0005 AC5 bans these in `.claude/skills`, `tracker/templates`, `AGENTS.md`, `SETUP.md` and `main.luau`: "git switch main", "runs on main before any PR", "root is on another branch", "git diff main...HEAD", "ExitWorktree", "wrapping it in a placeholder raft", "which gets a placeholder raft", "creates a placeholder raft", "wrap a single issue with", plus the four the raft lists.
- This raft is exactly where they get written. c0069 deletes the placeholder-raft path, so a `main.luau` comment "prompt never creates a placeholder raft" is likely. The launch-raft skill is about entering a worktree, so "don't use EnterWorktree/ExitWorktree" is likely too.
- RC0 runs only the members' check.sh files, so c0005's AC5, c0053's AC8 (F4) and the edited c0045, c0046 and c0047 checks are never run, and a regression in them lands silently.

Critique: listing the phrases helps, but the next edit to c0005 drifts again.
Consequences: running the done check.sh files costs gate time. c0053's AC4 alone reruns every acceptance and tooling spec.
Recommendation: copy c0005's full banned list into the Wording rule, and make c0067 AC10's scan use it. Add an RC5 that runs the five overridden done check.sh files (`bash tracker/issues/done/c0005/check.sh` and the others). If that is too slow, cover c0053 with a targeted grep for its AC6 and AC8 conditions instead.

### F10 [low] Missing spec cases for documented refusals
Where: ready.spec, stop.spec, prompt.spec.
Evidence: no case covers:
- `ready` with the main checkout on a branch other than `main` (c0067 step 2);
- a member that is `prepared` but not `design: ready`;
- `stop` with a member already in `done/` (c0068 step 2);
- `status <readied> new|preparing` (only `prepared` is tested, so a mutant that refuses only `prepared` passes).

c0069's "reads any file that exists" mutant is killed only by the wording of the error message, because R0002 has no prompt.md.
Recommendation: one assertion each. For c0069, the stale-prompt case from F2.

### F11 [low] Smaller gaps against the user's decisions and the docs
Evidence:
- Decision 2 says stop "names them" (the branch and the PR). c0068 prints the branch and a generic "its pull request". On a GitHub origin it can name the PR with `gh pr list --head <branch> --json url`.
- AGENTS.md's Non-negotiable sentence still says "the main checkout is never edited", while `ready` and `stop` pull it and write `prompt.md`. Only the table row is planned to change.
- c0070's timing fallback (`PICKMAN_BOARD=0` set by `tests/run`) edits `tests/run.luau`. That file is not in c0070's Touched modules, and R0021 (active) is editing it.
- A worktree for R created before `ready` (its branch still has R in the backlog) makes `start` take the legacy path and fail with "is active on origin/main, not prepared". The message should say to run `tracker.sh sync` first.

Recommendation: fold each into the owning issue's Design (c0068 report line, the AGENTS.md sentence in c0067, `tests/run.luau` in c0070's Touched modules or a different fallback, the start message in c0067).

Verdict: changes
