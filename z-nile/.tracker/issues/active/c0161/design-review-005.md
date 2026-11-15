# Review 005: c0161 (design mode)
Inputs: worktree prep-closure-skips-design-review at c199e8de plus its uncommitted item folder: c0161.md, check.sh, acceptance/{review-rule,review-gate,review-raft,review-read,design-record,docs}.spec.luau, experiments/{proto-engine,proto-fixtures,proto-skills}.patch, experiments/mutants.py, proposed-lessons.md, design-review-001..004, design-refute-001..004, harvest.md and spend.md. `./zn capture c0161` gives b473d45c, a confirmed capture (Problem only). The prototype clone (/var/folders/b1/97q05hyx277_zqbc5mcchvlw0000gn/T/tmp.PDPCmUR36g/p): its `git diff` of engine, skills and tests equals the three patches byte for byte (index lines aside), its acceptance/ equals the worktree's, and its numstat is +276/-16. I read `setStatus`, `keepRecords`, `refuseUnraftable`, `cmd.fold`, `cmd.recombine`, `raftingStart`, `cmd.new` (new raft), `cmd.ready`, `moveOnOrigin`, `originFolderFiles`, `cmd["raft-plan"]`, `ids.rewrite`, `raftplan.recordHash` and the skill diffs. origin/main is at e886f94a (I fetched it: c0181 is `prepared` and R0074 `issues: [c0181]` is `preparing-violet-amber-mongoose` with an empty Theme; R0075 to R0077 are rafts over prepared, exempt issues). Lessons: `./zn lessons --when design --full` (143 lessons) and `./zn lessons --skill zz-review --full`; `./zn lessons --uncovered c0161` says "every finding is covered". Runs: two unlisted mutants against review-read.spec, on a scratch copy of the prototype that I deleted afterwards (F1). The record quote is waived: `./zn design-record` is not landed (it exists only in the prototype, not in this worktree), so this round quotes no `Design record:` line.
Dropped from design-review-004: F1 (K9, K10 cases and rows), F2 (literal designHash pin, K11), F3 (`status.roundLines` is the one reader, used by the rule, `preparedReadProblem` and `keepRecords`; `rewriteRecord` is line based), F4 (`refuseInMainCheckout("design-record")`, the case, F4x), F6 (z-design 5.4 gives the user's options, the 001-to-006 case), F7 (the user's "Check at next read" decision; accepted risks 1 and 2 rewritten; the Non-goal's number fixed), F8 (fixed in the places named; two engine comments were missed, repeated in F6 below), F10 (`size: 290` against 292 changed lines). F5 is fixed in z-design 5.2 but not in zz-review (F6 below). F9's carrier is named, but its moment is now (F4 below).

### F1 [high] AC7 can be passed by a wrong implementation: no case has `ready` take a matching quoted member, and no case runs `recombine`, which the user's decision names; both mutants survive
Where: AC7 ("`new raft`, `fold` and `ready` refuse …, take a matching one, and take an issue none of whose rounds quotes a record as before"); the Problem's "Check at next read" line ("`fold` (and `recombine`, which shares its check)"); Design part 5; review-read.spec; Rules and mutants rows R4, R5, N1x to N3x.
Evidence:
- review-read.spec has one `ready` case (c0955, edited, expects a refusal) and no `recombine` call. `new raft` and `fold` each have a refuse case and a take case; `ready` has no take case.
- Mutant "ready compares with a wrong record" (in `cmd.ready`'s callback, `local stale = preparedRead(m.id, mfiles)` replaced by `statusLib.preparedReadProblem(mfiles, "000000000000")` with the id prefixed). It refuses every member whose rounds quote a record, so after c0161 lands no raft of newly prepared issues could be readied. Result: review-read.spec 5 passed, 0 failed. No other spec reaches it, because no existing fixture quotes a record (`tooling/ready-members` and `c0116/*` members are exempt).
- Mutant "the check sits in `cmd.fold`, not in `refuseUnraftable`" (the `preparedRead` lines moved from `refuseUnraftable` into `cmd.fold`'s loop). `recombine` (`refuseUnraftable(m, keeper)`, main.luau about line 1992) then reads no record. Result: review-read.spec 5 passed, 0 failed. N2x ("the fold/recombine call removed") only removes the shared call, so it cannot tell the two apart.
- A plausible slip that the first mutant stands for: computing the record from the tree after `moveOnOrigin` rewrites `check.sh`. The spec's `CHECK` holds no path of its own folder, so even a take case with that `CHECK` would not see it.
Critique: lessons z-design/spec-design-correspondence and zz-test/seed-every-enumerated-case. The Design names four readers; the spec seeds three refusals and two takes. The tempting fix is a `ready` take case with the current `CHECK`, which still passes a reader of the rewritten tree.
Consequences:
- `ready` runs from the main checkout and moves the raft to `active/`, so the take case needs its own raft (R0962) and must come after the cases that use the backlog.
- `recombine` needs two prepared backlog rafts that already hold members (`recombine <keeper> <other> [<issue>...]`).
- AC7 and its check.sh label gain `recombine`. The sequestered check.sh can still change in prep.
Recommendation: in review-read.spec, each with a Rules and mutants row and a runner entry:
- (a) `ready R0962` succeeds when its member's newest round quotes the matching record and the member's `check.sh` names its own backlog folder literally (so the move rewrites it). Mutant N4x: "ready compares with a record other than the one on origin/main", the mutant above.
- (b) `recombine` refuses to move a member edited after its quoted round, naming the member and the file, and moves a matching one. Mutant N5x: "the check in `cmd.fold`, not in `refuseUnraftable`".
- Add `recombine` to AC7 and its check.sh label, and run both mutants.
Lesson: z-design/spec-design-correspondence

### F2 [medium] `raft-plan` plans stale issues, so `raft-plan --apply` stops part-way, after earlier commands have published claims
Where: `cmd["raft-plan"]` (main.luau about line 3640: `issues` built from `store.all("issue")` with status, design, raft, size, solo and touched modules); `raftplan.plan`; Design part 5; the lessons pass in Unknowns & experiments ("new-refusals-reach-every-caller (… `raft-plan --apply` which only runs `new raft`/`fold`; AC3)").
Evidence:
- `raft-plan` gives `raftplan.plan` no sign of a stale record. So a prepared, raftless issue whose newest quoted round no longer matches is planned into `./zn new raft …` or `./zn fold …`.
- `--apply` then calls `cmd[...]` for each command in order, and the new check `fail`s inside the first command that holds the stale issue.
- Every command before it has already published its claim on origin/main (`new raft` and `fold` publish the raft's `preparing` stamp) and written `raft:` lines locally. The lead is left with a half-applied plan to finish or undo by hand.
- The lessons pass checked the move refusal against `raft-plan --apply`, not the check at next read added in round 4.
Critique: lesson z-design/new-refusals-reach-every-caller. `raft-plan` already prints `skip <id>: <why>` for issues it cannot place, and a stale design is one of them. The tempting fix is to let `--apply` carry on past a refusal, which leaves the plan's grouping wrong (a raft planned with the stale issue in it).
Consequences:
- `raftplan.plan` is pure. The stale reason enters as an optional field of `raftplan.Issue` (for example `stale: string?`), so the c0116 plan specs that build Issue tables stay valid.
- The field is computed with the same `preparedRead`, on the folder as it is on origin/main (`originFolderFiles`). The cost is one read per prepared, raftless issue (about 30 today), and only folders holding a `design-review-` file need the read.
Recommendation:
- `raft-plan` puts a stale issue on its skip list: `skip <id>: prepared on origin/main but <file> … (z-design: a new round)`. `plan` never places it.
- Add a review-read case: a stale prepared issue appears as `skip`, and a matching one is planned. Add a Rules and mutants row with mutant "raft-plan ignores the record".
- Name the caller in the lessons pass.
Lesson: z-design/new-refusals-reach-every-caller

### F3 [medium] An approving round 5 whose low findings are answered by an edit has no way through: the engine refuses it as stale, and z-design sends only a `changes` round 5 or a high to the user
Where: z-design 5.3 ("Answering a finding by an edit needs a new round"); 5.4 ("round 5, which is always final"; "a round 5 that says `changes`, or holds a high, goes to the user"); 5.5; `designReviewProblem` (stale quote).
Evidence:
- zz-review allows `approve` with low findings ("Use `approve` only when no high or medium findings remain"), and 5.3 says "Answer every finding".
- Suppose round 5 approves with one low, and the author answers it `fixed`, which is an edit to the document. `status <id> prepared` then refuses ("quotes Design record …, but the design is now …"). 5.3 asks for a new round, but 5.4 caps the rounds at 5, and its route to the user covers only "says `changes`, or holds a high".
- This round's own brief reads the old rule: "Medium and low findings are answered `fixed` or `refuted` and the issue then goes `design: ready` if there is no high". Under the new engine that order is refused, and the skills give the lead no next step. The lead either stops or edits the quote by hand, which is accepted risk 1 made routine.
Critique: lesson z-design/required-steps-on-every-path, on the path through the cap. Round 4's F6 fix covered a `changes` round 5, not an approving round 5 that is then edited.
Consequences: no engine change. A refuted low leaves the design as quoted, so the round stays final. A low fixed by an edit needs round 6, which is the same user decision as a `changes` round 5.
Recommendation:
- In z-design 5.4, say that a round 5 that says `changes`, holds a high, or has a finding you answer by an edit goes to the user, with the same options.
- In 5.3, add: "an approving final round's findings answered by a refute keep it final; answered by an edit, they need the next round".
- Pin both sentences in docs.spec.
Lesson: z-design/required-steps-on-every-path

### F4 [medium] (repeat of design-review-004 F9, with new evidence) The Theme line that carries the one-file-set decision to c0181 has to be written now, and R0074's Theme is empty
Where: Shared state, the c0181 bullet ("the note travels as a line of the Theme of the raft z-raft makes for c0181 … The lead puts that line there when c0181 is rafted").
Evidence:
- On origin/main at e886f94a, `R0074.md` has `issues: [c0181]`, `status: preparing-violet-amber-mongoose`, `design: draft` and an empty `## Theme`. So c0181 is being rafted now, by a z-raft lead who reads c0181.md and z-raft, not c0161.md.
- `git show origin/main:z-nile/.tracker/rafts/R0074/R0074.md | grep -n 'c0161\|recordPaths\|spec-hash'` finds nothing.
- c0161's lead finishes its prep before R0074 lands or after it, and the Design names neither R0074 nor what happens if its rafting PR lands without the line. If it does, c0181's executor writes its own `spec-hash` file list beside `recordPaths(…, true)`: two definitions of "the specs a proof covers".
Critique: lessons z-design/results-land-on-every-path and z-design/quote-other-preps-before-promising. The carrier is named, but the moment it depends on is already open.
Consequences: none for c0161's own behaviour. The fallback is a capture, which needs no scope decision.
Recommendation:
- Name R0074 in the c0161 bullet. Say that c0161's lead hands the Theme line to R0074's rafting lead now.
- If R0074 lands without the line, the lead captures a chore with `./zn new issue c …` ("c0181's spec-hash hashes `raftplan.recordPaths(id, files, true)`") and records its id in Shared state.

### F5 [low] The `reasoned` row for fold's reader rests on a false reason: a committed local edit in the rafting worktree tells `originFolderFiles` from the work tree
Where: Rules and mutants, the row "`fold`/`recombine` read the issue as it is on `origin/main` (`originFolderFiles`) …: reasoned: the tool requires a clean tree for `fold` and syncs before `new raft`, so the work tree and `origin/main` hold the same files in every state a case can reach".
Evidence:
- `raftingStart` refuses a dirty tree, then runs `git merge --no-edit origin/main`. A commit in the rafting worktree that edits a prepared issue's Design survives that merge.
- So the case is reachable: commit an edit to c0953 in `wt`, then `fold R0960 c0953`. The origin reader takes it (origin matches the quote), while a work-tree reader (`gitFolderFiles(issue.dir)`) refuses it.
- z-raft's own lesson ("A rafted member's fix is made in the raft and folded again") says rafting worktrees do edit members.
Critique: lesson z-design/reasoned-rows-claim-testable-reasons. The decided reader is origin (the user's decision says "as on origin/main"), so the behaviour is right but unpinned, and a mutant that reads the work tree survives.
Consequences: the local edit then lands with the rafting PR and is judged at `ready`. Accepted risk 2(d) should say so.
Recommendation:
- Make the row `run`: a review-read case where fold takes an issue whose local committed edit is not on origin/main. Mutant: "fold reads `gitFolderFiles(issue.dir)`".
- Add one sentence to accepted risk 2(d): an edit made in a rafting worktree is judged at `ready`.

### F6 [low] Restated wording still disagrees with the mechanism in six places
Where and evidence:
- Non-goals bullet 4 says "`ready`, `stop` and `release`: … the rule is on the move that makes an item prepared". But Design part 5 and AC7 run the check at next read in `ready`.
- zz-review's design-mode paragraph has no "everything under `experiments/` is part of the record" sentence (only z-design 5.2 does), although design-refute-004 F5 says "z-design 5.2 and zz-review say" it.
- Two engine comments in proto-engine.patch still describe an approving-only quote. `raftplan.designRecord` says "A reviewer who approves quotes it", and `cmd["design-record"]` says "the hash a reviewer quotes when approving". Every design round quotes it (z-design 5.2, zz-review).
- Implementation step 5 says "`./zn check c0161` (AC1 to AC6)", but check.sh has AC7.
- Scalability says "`ready` [is] unchanged". `ready` now hashes each member once more, and `fold` now lists and reads each issue's folder on origin/main a second time (`originFolderFiles`, besides `recordGrouped`'s).
- Accepted risk 1 cites `git grep -n designReviewProblem -- z-nile/engine` for "the single call site of the move rule". That grep now also lists the call inside `preparedReadProblem`, so the premise needs "in main.luau".
Critique: lesson z-design/restated-rules-move-together.
Consequences: none.
Recommendation: reword each one. Keep `ready`'s check in the Non-goal ("… except the check at next read, Design part 5"). Add the experiments sentence to zz-review and pin it, or correct the refute's claim.
Lesson: z-design/restated-rules-move-together

Harvest: every entry in harvest.md names an existing lesson or a one-off with its reason, and the new lesson in proposed-lessons.md (existence-checks-exclude-earlier-cycles) is general (any existence check over a re-prepped item), not a restated finding. No harvest finding.

Candidate lessons (reviewer, for the lead to harvest):
- A note on z-design/spec-design-correspondence, from c0161 design review 005 F1. When one shared check is wired into N commands, the spec has a refuse case and a take case for each command, not for the shared function. Check: "For every caller the Design names, is there a case where the caller takes the good input, and one where it refuses the bad?"
- A note on z-design/new-refusals-reach-every-caller, from c0161 design review 005 F2. A refusal added to commands that a planner composes (`raft-plan --apply`) also goes into the planner's skip list, or the apply stops after earlier commands have published. Check: "Does a planner build arguments for the command this refusal is in, and does it skip what the refusal would refuse?"

Verdict: changes
