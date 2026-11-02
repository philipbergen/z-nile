# Review 006: c0161 (design mode)
Inputs: worktree prep-closure-skips-design-review at c199e8de plus its uncommitted item folder: c0161.md, check.sh, acceptance/{review-rule,review-gate,review-raft,review-read,design-record,docs}.spec.luau, experiments/{proto-engine,proto-fixtures,proto-skills}.patch, experiments/mutants.py, proposed-lessons.md, harvest.md, design-review-001..005 and design-refute-001..005. `./zn capture c0161` gives b473d45c, a confirmed capture (Problem only); the Problem keeps it and adds four `Decided with the user` lines. Prototype: /var/folders/b1/97q05hyx277_zqbc5mcchvlw0000gn/T/tmp.PDPCmUR36g/p (its acceptance/ equals the worktree's; I read `setStatus`, `keepRecords`, `preparedRead`, `refuseUnraftable`, `cmd.fold`, `cmd.new`, `cmd.ready`, `moveOnOrigin`, `originFolderFiles`, `raftingStart` and `cmd["raft-plan"]`). origin/main as fetched locally is 6145abab. Lessons: `./zn lessons --when design` (143) and `./zn lessons --skill zz-review --full`; `./zn lessons --uncovered c0161` says "every finding is covered". Runs, on a `cp -c` copy of the prototype that I deleted afterwards: two unlisted mutants of `raft-plan` against review-read.spec (F1), and a scratch spec that runs `raft-plan` with and without an origin remote, on the prototype's engine and on the base engine (F4). The record quote is waived: `./zn design-record` is not landed (it exists only in the prototype, not in this worktree), so this round has no `Design record:` line.
Dropped from design-review-005: F1 (the `ready` take case with a `check.sh` that names its own folder, and the `recombine` refuse/take case; N4x and N5x run), F3 (z-design 5.3 and 5.4 now cover an approving round 5 answered by an edit, pinned), F4 (R0074 is named; what changed since is in F3 below), F5 (the fold origin-reader case and N7x; accepted risk 2(d)), F6 (all six rewordings are in). F2's skip list is in, but its "plans a matching one" side is not pinned (F1).

### F1 [high] (repeat of design-review-005 F2, in part) AC7's "raft-plan … plans a matching one" can be passed by a wrong implementation: a `raft-plan` that skips every issue with a quoted round passes review-read.spec
Where: review-read.spec.luau lines 114-126 ("raft-plan puts a stale prepared issue on its skip list and plans a matching one"); AC7; Rules and mutants row "`raft-plan` skips a stale issue and plans a matching one" (N6x).
Evidence:
- The case's only check on the take side is `t.expect(has(r.stdout, "c0950")).toBe(true)`. A `skip c0950: …` line satisfies it as well as a planned command.
- I ran the mutant "`raft-plan` compares with another record". In `cmd["raft-plan"]` I replaced `planned.stale = statusLib.preparedReadProblem(files, raftplan.designRecord(it.id, files))` with `… preparedReadProblem(files, "000000000000")`. Result: review-read.spec 9 passed, 0 failed. Its raft-plan output was:
  `./zn fold R0960 c0952`
  `skip c0950: is prepared on origin/main but design-review-001.md quotes Design record 89d63f8ad29a, but the design is now 000000000000: …`
  and the same skip for c0951, c0953, c0954 and c0961. So every issue that has a quoted round was skipped, and only the exempt c0952 was planned.
- The mutant stands for a plausible slip: a record taken over the wrong file set, or with the wrong id. After c0161 lands, every newly prepared issue quotes a record. With this slip, `./zn raft-plan` (z-raft's no-argument default) would place none of them, and nothing in the gate would notice, because no other spec gives raft-plan a quoted round.
- A second unlisted mutant also survives: "`raft-plan` reads the work tree" (`originFolderFiles(it.dir)` replaced by `gitFolderFiles(it.dir)`) gives 9 passed, 0 failed. raft-plan runs before the case that commits c0961's local edit, so at that point the work tree and origin are the same. Design part 5 says raft-plan reads the folder "as on `origin/main`" so that it agrees with `fold`, but nothing pins that.
Critique: lessons zz-test/refusals-tested-on-both-sides and zz-test/no-vacuous-pass. This is the third round in which a "take" side of the check at next read is unpinned (round 5 F1 found it for `ready` and `recombine`). The mechanism keeps failing in one way: a take assertion that only looks for the id in the output. The tempting fix is to assert `./zn` somewhere in stdout, which an exempt-only plan (`./zn fold R0960 c0952`) already satisfies.
Consequences:
- The case has to name a matching quoted issue in a command line, and must also check that no skip line names that issue.
- The plan groups all raftless prepared chores of pickman into one command, so c0950, c0953 and c0961 appear in the same `./zn` line. The assertion should be per id, not one exact line, so that the case does not pin raftplan's grouping (lesson zz-test/promoted-specs-pin-rules-not-sets).
- A reader case needs an issue whose committed local edit is not on origin/main at the moment raft-plan runs. That means a second raft-plan call after the c0961 commit, or its own issue.
Recommendation:
- In review-read.spec's raft-plan case, for each matching quoted issue (c0950, c0953, c0961), assert that some line starting `./zn ` names it and that no line starting `skip <id>:` does.
- Add a case that runs `raft-plan` again after a committed local edit to a quoted prepared issue (not on origin/main). It must still plan that issue.
- Add Rules and mutants rows and runner entries for both: N8x ("raft-plan compares with another record") and N9x ("raft-plan reads the work tree"). Run them.
- Because the same hole has now appeared three times, check every take assertion in review-read once more: for `new raft`, `fold`, `recombine` and `ready`, does it assert the accepted result (exit status and the item's new place), or only that the id appears?
Lesson: zz-test/refusals-tested-on-both-sides, zz-test/no-vacuous-pass

### F2 [medium] The check at next read refuses an edited prepared issue, but nothing tells anyone how to recover, and z-raft's own documented path for fixing a member walks straight into the refusal
Where:
- Design part 5.
- Usability ("Every refusal names … the step of z-design that explains it, so the person fixes it without reading the code").
- The refusal text: "run a new round (z-design 5.3 …)", and raft-plan's "(z-design: a new round)".
- z-raft's new bullet "… send it back to z-design".
- Lesson z-raft/rafted-member-changes-stay-in-the-raft.
Evidence:
- That z-raft lesson is the documented way to change a rafted member's design. Claim the raft with `fold`, make the member's change in the rafting branch, fold it again at the end so `grouped:` matches, then `./zn status <R-id> prepared` and land.
- Under c0161, every step of that path passes:
  - The re-fold reads origin/main, where the member still matches its old quote (review-read's c0961 case pins exactly this).
  - The carried raft move takes a prepared member as it is (row P1 pins that it asks nothing of it).
  - CI runs nothing that reads the record.
- The rafting PR lands, and `./zn ready` then refuses the member. The c0955 case pins this.
- The refusal says "run a new round (z-design 5.3 …)", but z-design 5.3 describes answering a round in a prep. For an issue that is in a raft, z-design's claim refuses (`status <id> preparing` refuses an issue whose `raft:` names a raft), so the way back is `unfold`, a landed PR, a reclaim, a round, a prep PR, a re-fold and a coherence review. No skill says so.
- The cheaper path the engine allows is to add a member design round in the same rafting branch. `design-record` works in any worktree but the main checkout, and the newest round then quotes the edited record. No skill says that either.
- The trigger is routine. R0078 (active on origin/main) is c0173 and c0174, two chores whose Touched modules are c0075's and c0083's design documents and acceptance specs, two prepared issues. They are exempt today only because no round of theirs quotes a record. After c0161 lands, the same chore aimed at a newly prepared issue stales it, and the refusal appears only when someone next rafts or readies that issue.
Critique: lesson zz-arch/refusals-are-gate-checks ("If one lands anyway, where is the recovery written, and does it work while the tool refuses?"). The refusal is right, by the user's decision. The defect is that its recovery is unwritten and that the skills' own member-fix path produces it. The tempting fix is a sentence saying "send it back to z-design". For a rafted issue that is a claim the tool refuses.
Consequences:
- Writing the in-raft round into the member-fix path changes z-raft and its lesson's "How to apply". The member's round goes in the member's folder in the rafting branch, before `status <R-id> prepared`, so it also enters the member's `grouped:` record. The re-fold must therefore come after that round, which the lesson's ordering note already asks for.
- A chore that edits another prepared issue's design files needs the same instruction: a round of the edited issue, run in the chore's worktree and landed with the edit.
- If the carried raft move were also to run `preparedRead` on each prepared member's local folder, the rafting PR could not carry a stale member at all. That adds a fifth reader to the four the user's decision names. It cuts nothing, but it is a decision for the lead to record.
Recommendation:
- Write the recovery where it is met:
  - z-raft §2 and the lesson z-raft/rafted-member-changes-stay-in-the-raft: "a member whose design changes in the raft gets its own design round in the rafting worktree, quoting the edited record, before the re-fold".
  - z-design, or zz-rules' Rafting bullet: "a stale prepared issue is made current by an approving round that quotes its record, run in the worktree that holds the edit and landed with it; a rafted one is otherwise unfolded and reclaimed".
  - The text of `preparedReadProblem` / raft-plan's skip, which should name that step instead of z-design 5.3 alone.
- Pin the sentences in docs.spec. Add a review-read case in which an approving `design-review-002.md` quoting the edited record lets `ready` (or `fold`) take an issue whose 001 is stale.
- Name the R0078 shape (a chore that edits another prepared issue's specs) in Existing work.
- Optionally run `preparedRead` in the carried raft move for prepared members, with a case and a mutant, recorded as the lead's choice beside the user's decision.
Lesson: zz-arch/refusals-are-gate-checks

### F3 [medium] (follows design-review-005 F4) R0074 now says "whichever of c0161 and c0181 executes second wires the shared function", but c0161's documents only cover c0181 coming second, and Shared state misses three active rafts on the same files
Where: Shared state (the c0181 bullet; the list of in-flight work); Implementation steps; Touched modules.
Evidence:
- On origin/main at 6145abab, R0074 is `prepared-falcon-violet-amber` with `grouped: [c0181@21e9aa1e5066]`. Its Theme says "c0181's spec proof … hashes `raftplan.recordPaths(id, files, true)` (c0161) … whichever of c0161 and c0181 executes second wires the shared function". Its Whole-raft design repeats "**Whichever of c0161 and c0181 executes second wires the shared function.**"
- c0161's Shared state still says R0074 is `preparing-violet-amber-mongoose` with an empty Theme, and that "if R0074 lands without it, the fallback is a captured chore".
- c0161's documents give its executor no step for the case where c0181 is already on origin/main. Neither Implementation steps nor Touched modules mention c0181's `./zn prove` code. A c0161 executor who comes second will never read R0074's Theme, because the prompt z-ready builds for c0161's raft does not include it.
- That order is the likely one. R0074 depends on c0136, whose raft R0068 is active now, while c0161 is still in prep.
- Shared state was "read … on 2026-11-01" and lists c0136, c0181, R0061, c0139, c0141, c0083 and c0178. Since then R0070 (c0194), R0071 (c0191) and R0075 (c0184) were readied, and all three touch `z-nile/engine/main.luau` and z-design, zz-review or zz-rules (their Touched modules on origin/main).
- c0184 also edits `c0111/skill-docs.spec`, `c0114/docs.spec` and `c0115/docs.spec`. c0161's Regression guard and E5 say c0161's skill wording was fitted to pins in two of those specs.
Critique: lessons z-design/quote-other-preps-before-promising and z-design/results-land-on-every-path. The agreement now exists on R0074's side only. If c0181 lands first, two file sets ship, which is the outcome the "one file-set function" decision exists to prevent.
Consequences:
- c0161 gains a conditional step and a conditional Touched path: c0181's prove module, if it is on origin/main at execution.
- c0181's specs are among those to run. Its `spec-hash` covers the same set (`check.sh` and `acceptance/**`), so its promoted pins should stay green, and no `Overrides:` change is needed. The executor must still check that, and stop if a pin turns red.
Recommendation:
- Update the c0181 bullet with R0074's current state and quote its line.
- Add to Implementation steps: "if c0181's `./zn prove` is on origin/main, make its `spec-hash` file list `raftplan.recordPaths(id, files, true)` and run its prove specs".
- Add the path to Touched modules as conditional, and have z-raft carry the same line into c0161's raft Theme.
- Add c0184, c0191 and c0194 to Shared state, each with the hunks it shares, and note that c0161's skill wording must be refitted to c0184's edited docs pins if c0184 lands first.
Lesson: z-design/quote-other-preps-before-promising

### F4 [low] `./zn raft-plan` now fails in a checkout with no origin remote, where it used to print the plan; Usability says "Offline, nothing changes"
Where: `cmd["raft-plan"]` (`originFolderFiles(it.dir)` for each prepared, raftless issue); `originFolderFiles` (`fail("cannot list … on origin/main to record what was grouped")`); Usability.
Evidence: I ran a scratch spec. It sets up one prepared issue with a quoted approving round, runs `raft-plan` in the fixture's main checkout, runs `git remote remove origin`, and runs `raft-plan` again.
- Prototype engine, no origin: `ok=false`, `cannot list pickman/.tracker/issues/c0950 on origin/main to record what was grouped`.
- Base engine (c199e8de's main, status and raftplan), no origin: `ok=true`, `./zn new raft chore c0950 c0950 --project pickman`.
Critique: low, not high. Every command the plan prints (`new raft`, `fold`) already refuses without an origin (`raftingStart`: "needs an origin remote"), so nothing a user could finish is lost. Still, the claim is false, and the message blames "what was grouped".
Consequences: if raft-plan skips the check when origin/main is missing, the plan can list an issue that `new raft` would refuse. That is harmless, because `new raft` cannot run there either.
Recommendation:
- In raft-plan, compute `stale` only when the origin/main ref exists (`git rev-parse --verify -q origin/main`), and leave it nil otherwise.
- Correct the Usability sentence.
- A case is optional: plan-cli is the place for it, but it is promoted and an override for a low finding is not worth it, so a sentence will do.

### F5 [low] Two restatements of what the commands refuse were not updated, and the skip reason repeats its hint
Where and evidence:
- z-ready step 2 says "`./zn ready` enforces every rule below …; read them so you can explain a refusal", and its list does not have the new refusal. `git diff` of the prototype shows no z-ready change.
- z-raft §1 lists raft-plan's skip reasons ("an issue with no `size:` is skipped and named: send it back to z-design"), and the new stale skip is not there. The new z-raft bullet names only `new raft`, `fold` and `recombine`.
- The skip line reads "… run a new round (z-design 5.3: a Design changed after a round, or by answering one, needs a new round) (z-design: a new round)": the second parenthesis repeats the first.
Critique: lesson z-design/restated-rules-move-together.
Consequences: z-ready joins the Touched modules and the docs pins.
Recommendation:
- Add the refusal to z-ready step 2's list and the skip to z-raft §1's policy list, worded with F2's recovery, and pin both in docs.spec.
- Drop raft-plan's duplicated suffix, or replace it with the recovery F2 names.
Lesson: z-design/restated-rules-move-together

Harvest: every round-5 entry in harvest.md names an existing lesson, with no restated finding, so there is no harvest finding. proposed-lessons.md has not taken round 5's two reviewer candidates (per-caller take and refuse cases; a planner's skip list). F1 shows the first one is still needed in a sharper form: a take assertion must check the accepted outcome, not that the id appears in the output.

Candidate lessons (reviewer, for the lead to harvest):
- A note on zz-test/no-vacuous-pass, from c0161 design review 006 F1. A "take" assertion on a command that prints both accepted and skipped items checks the line kind, not the id alone, because `has(stdout, id)` also matches a skip or refusal line. Check: "Would this take assertion still pass if the command refused or skipped the item and printed its id in the reason?"
- A note on zz-arch/refusals-are-gate-checks, from c0161 design review 006 F2. A refusal that fires at a later read (rafting, readying) needs its recovery written on every documented path that produces it, including the skills' own fix paths (a member fixed inside a raft). Check: "Which documented workflow can land the state this refusal refuses, and does that workflow say how to avoid or repair it?"

Verdict: changes
