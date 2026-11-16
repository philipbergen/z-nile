# Review 002: c0161 (design mode)
Inputs: worktree prep-closure-skips-design-review at c199e8de plus its uncommitted item folder (c0161.md, check.sh, acceptance/{review-rule,review-gate,review-raft,docs}.spec.luau, experiments/{proto-engine,proto-fixtures,proto-skills}.patch and mutants.py, design-review-001.md, design-refute-001.md, harvest.md); `./zn capture c0161` (b473d45c, a confirmed capture: Problem only); `z-nile/engine/{main,status,lessons}.luau` (`setStatus`, `new raft`, `fold`, `refuseUnraftable`, `lessons.findings`); the prototype clone (read only); `git ls-tree origin/main` for R0044, d0124 and c0181; the c0181 worktree (`prep-lessons-codify-consolidate`: its folder, `git status`, c0181.md); c0136's c0136.md; d0151's history; a rescan of the newest round of every folder on origin/main (84 folders: 43 approve, 41 changes, 39 with a refute, every one answering all ids; no refute for done/f0146 and for the non-item folder c0083/experiments/r0026-review-history); `./zn lessons --when design --full`. No spec was run: every claim below follows from reading the fixture and the code.
Dropped from design-review-001: F4 (fixed: each in-flight item is quoted with its outcome), F5 (fixed in the wording; the `audit` option is open for the user and its premises hold), F6 (fixed: the search is pasted, the header says AC4, the pinned sentences are quoted). F3's refutation of `done`'s `reviewProblem` is right and its real defect (an empty or partial refute) is fixed; one remaining part is F3 below.

### F1 [high] (repeat of design-review-001 F1) The scope-reset re-prep that z-design documents still passes on the earlier scope's round, because those rounds never reach origin/main; the Design says c0181 proves the opposite, and accepted risk 2 rests on a false premise
Where: Design part 1, "**This prep's round**"; Chore checklist, Existing work (last sentence: "c0181 is the live example: its earlier scope's rounds are on `origin/main`, so it needs a round numbered above them") and Shared state (c0181: "as a re-prep, will itself be refused until a round above its earlier prep's exists"); Accepted risk 2.
Evidence:
- c0181 is the live re-prep after a user scope reset. Its c0181.md line 195 says "the first five rounds, design-review-001 to 005, judged the earlier floor-based scope … its first new round is round 1 = `design-review-006.md`".
- In its worktree, `git status` lists `?? z-nile/.tracker/issues/c0181/design-review-001.md` … `005.md` and their refutes as untracked. `git ls-tree -r origin/main -- z-nile/.tracker/issues/c0181` lists only `c0181.md`, `check.sh` and `spend.md`.
- So with the prototype, `originFiles` holds no round. Before `design-review-006.md` existed, `designReviewProblem` judged 005 (`Verdict: changes`, answered by `design-refute-005.md`) and returned nil. A redesign of the reset scope, a closure included, would have been prepared on the old scope's review.
- Both c0181 sentences in the Design are false. They are the evidence the refute gives for F1 being fixed.
- The origin comparison catches one kind of re-prep only: a reclaim (`prepared` -> `preparing`) of an issue whose earlier prep landed. z-design 5.4's scope reset happens in place, in the prep worktree, before anything lands. That is the route F1 named ("c0181 … Before that file exists, the rule would pass c0181 on round 005").
- Inside one prep, a defect's fix design gets an approving round, the user's retest does not reproduce it, and the author rewrites the Design to "No code change". The move passes. That is the captured Problem word for word: a closure that skipped the design review.
- Accepted risk 2's premise is "z-design 5.4 already makes a changed-after-approval design a new round". That is false. 5.4 runs another round only on how a round was answered ("if any high finding was fixed or refuted, or answering the round was more than minor"). A rewrite after an approving round answers nothing.
- Neither 5.4 nor the new paragraph "A closure is designed and reviewed like any issue" says that a design changed after its final round needs a round. So the case passes the engine and the skills alike.
Critique: the origin comparison stands in for "the newest round read this design". It covers one of three ways a round goes stale (an earlier prep that landed), while the Design and the refute say it covers re-preps. Round 1 found the stale-round hole, and the fix has the same hole on the documented route (lesson: question the mechanism). The tempting fix is a second proxy, such as comparing with the prep branch's committed files or its base. It fails here: c0181's old rounds are untracked, and a closure decided after an approving round has no commit boundary at all.
Consequences: only a record of what the round read tells whether the newest round covers this design (accepted risk 2's open option). That record brings its own rules:
- It covers the design files, `raftplan.isDesignFile` less the reviews, refutes, `harvest.md` and `spend.md`.
- A `changes` round answered with fixes changes the design by design. So either only `approve` rounds are compared, or the refute records the answered design's record too.
- `compact`, `renumber` and `remap` rewrite ids, so they must re-record it (lesson zz-arch/records-cover-what-was-reviewed).
- Rounds written before the rule carry no record and must be exempt.
- zz-review's format gains a line, and that line gets a reader.
A cheaper engine check could read the starting file that 5.4 already makes a reset declare ("the issue's Unknowns & experiments says which file it starts at"). It catches a declared reset, not a skipped one.
Recommendation:
1. Correct the two c0181 sentences, and state the comparison's true reach: it catches the reclaim of a landed prep, not a scope reset in place and not a change after the final round.
2. In the skills (within this issue, no format change), z-design's closure paragraph and step 5.4 say: "A Design changed after its final round other than by answering that round's findings (a closure decided after a fix design was reviewed, a scope reset in place) needs a new round before `design: ready`; a reset in place numbers its first new round above the files already there". zz-review item 12 asks whether the newest round read the closure, not an earlier design. Pin both sentences in `docs.spec.luau`.
3. escalate to the user: rewrite accepted risk 2 on its true premises. It covers a scope reset in place (c0181's route) and a reviewed fix turned into a closure, which is the captured Problem's own case, so it is a narrowing, not only an edit-after-approval risk. Options:
   - (a) A design record in every design round, with the consequences above: about 60 to 100 lines, a zz-review format change, a `./zn` line that prints the record, and cases for approve-match, approve-mismatch, a changes round with its refute's record, and re-recording after `compact`.
   - (b) The engine reads the reset's declared starting file: about 10 lines and 2 cases. It catches a declared reset only.
   - (c) Keep the engine as designed and record a `Scope decision (user, YYYY-MM-DD)` line in the Problem saying a closure decided after an approving round in the same prep is caught by the skills only.
   Under (a) or (b), add Rules and mutants rows for the new rule. Until the user answers, the issue does not go `design: ready` (z-design 5.5: anything else goes to the user first).
Lesson: z-design/required-steps-on-every-path

### F2 [high] (repeat of design-review-001 F2) R0044's shape is not pinned: no case puts the raft's rounds on origin/main, row L3's recorded observation is false, and the runner's L3 is a different mutant; the fallback also excuses an unanswered round in the member's own folder
Where: `acceptance/review-raft.spec.luau` cases 3 and 4; Rules and mutants row L (L1, L2, L3, `reasoned`); `experiments/mutants.py` entry L3; `proto-engine.patch` (`legacy` block); design-refute-001 F2 ("two review-raft cases (one with the raft's rounds already on origin, as R0044's are)").
Evidence:
- **The raft's rounds never reach origin in the spec.** Case 3 writes `{rdir}/design-review-001.md` and its refute with `fs.writeFile` in the fixture's prep worktree. Case 4 commits them there (`fixture.git(wt, { "commit", … })`), which pushes nothing. `trackerfix.elsewhere` is used only for c0900. So origin's raft folder holds only the `R….md` and `check.sh` that `new raft` published, and `treeFolderFiles` of it has no round.
- **A wrong implementation passes AC3.** Replace the literal `nil` in `statusLib.designReviewProblem(gitFolderFiles(store.get(id).dir), nil)` with the raft folder's files on origin. All five cases still pass, because origin holds no round there. On the real tree that implementation refuses `status R0044 prepared` ("design-review-005.md is from an earlier prep …"), since `git ls-tree origin/main` lists R0044's `design-review-001.md` to `005.md`. That is round 1 F2's regression.
- **Row L3's reason is false.** It says "the case lands the raft's rounds on `origin/main` and still passes", and the case does not.
- **The runner's L3 is another mutant.** It turns `if legacy then nil else treeFolderFiles(paths, read, folder)` into `treeFolderFiles(paths, read, folder)`, where `folder` is the member's own folder, not the raft's. For a member with no round of its own, both forms give "has no design-review-001.md" before any comparison, so this mutant is equivalent on every case, which is why it survived. The raft-folder comparison the row names has no runner entry.
- **The fallback excuses an unanswered round in the member's own folder.** Take a stamp-carrying member whose own folder holds `design-review-001.md` `Verdict: changes` with no refute, while the raft's folder holds an approving round. `problem` is set, `legacy` is true, `raftProblem` is nil, and the member passes. No Design sentence or case decides this.
Critique: lessons z-design/reasoned-rows-claim-testable-reasons (the reason must be tried, and here it is observable) and z-design/mutant-ids-match-the-runner. The tempting fix is a better-worded `reasoned` row. The behaviour is observable, so it needs a case.
Consequences:
- A case with the raft's rounds on origin must publish them with `trackerfix.elsewhere` after `new raft`, then `sync` in the worktree. The same files must not also be written locally first, or the merge conflicts with untracked copies.
- The own-folder rule needs a decision. I suggest: the member's own folder decides whenever it holds a round, judged like any issue (origin compared). The raft's folder, with no comparison, counts only when the own folder holds none. That is R0044's shape, since d0124's folder holds no round. The zz-rules sentence "judged by its own folder, or else by the raft's" stays true. The Design's part 1 sentence ("judged by its own folder with no origin comparison, else by the raft's folder the same way") changes.
Recommendation: add these review-raft cases:
1. R0044's shape. The raft's `changes` round and its refute are landed on origin by `elsewhere`, and the member has no round: `status <R> prepared` passes.
2. A stamp-carrying member's own folder holds an unanswered `changes` round while the raft's folder approves: refused, naming the member's file.
3. Following the decision above, the member's own folder holds an approving round that is on origin only: refused as an earlier prep's.

Add these runner entries, with ids equal to their rows:
- L3: the raft's call compared with origin, killed by case 1.
- L4: the fallback taken when the own folder holds a round, killed by case 2.
- L5: the own folder not compared, killed by case 3.

Run them on the prototype, record the results in Unknowns & experiments, mark the rows `run`, and correct design-refute-001 F2's claim in the Design's record.
Lesson: z-design/reasoned-rows-claim-testable-reasons

### F3 [low] (repeat of design-review-001 F3, in part) The finding-heading reader is a third copy of `lessons.findings`, and the Design says nothing else reads it
Where: `proto-engine.patch` (`status.designReviewProblem`, the `\n###%s+(F%d+)` loop and the `^design%-review%-(%d%d%d)%.md$` pattern, plus its comment "this reads the design pair, which nothing else judges"); Design, Maintainability ("Nothing else parses the round").
Evidence: `z-nile/engine/lessons.luau:134` `lessons.findings(review)` is a pure reader of the same `### F<n>` headings with the same pattern ("the pattern tracker.sh done reads"). Its private `isStem` holds the same three-digit round name. The refutation of `done`'s `reviewProblem` is right, but `lessons.findings` is the reader of this exact format, and neither the comment nor Maintainability names it.
Critique: lesson zz-arch/one-reader-per-format ("reuse the existing reader, or match it exactly and say so"). The pattern matches today. It is unnamed, so the next change to one reader leaves the other behind.
Consequences: `status.luau` has no requires, while `lessons.luau` requires `@lune/fs` and three modules at load. So the shared reader belongs in the pure side: `status.luau`, or a small pure module.
Recommendation: move the heading reader and the round-stem pattern into one pure function, and make `lessons.findings` call it. Or keep the copy and name `lessons.findings` and `lessons.isStem` in the comment and in Maintainability. Either way, add a review-rule case on headings where a looser or stricter reader would differ (`### F1: claim`, `### F10 [low]` beside `- F1:`).
Lesson: zz-arch/one-reader-per-format

### F4 [low] Wording and labels: the refusal's hint leads to a wrongly numbered round, a Non-goal cites the wrong risk, and three check labels say less than their specs verify
Where: `status.designReviewProblem`'s earlier-prep message; Non-goals bullet 2; `check.sh` AC1 to AC3 labels.
Evidence:
- The message ends "(z-design step 5; a re-prep restarts the count)". An author who reads it writes `design-review-001.md` again, which is still not above origin's newest, and is refused again. 5.4 means that the round count restarts, not the file number.
- Non-goals bullet 2 says "(accepted risk 2)". Accepted risk 2 is now about a Design changed after its approving round. The prepared issues that predate the rule are risk 5, and the `audit` option is risk 3.
- check.sh labels:
  - AC1's label leaves out the reclaimed issue whose round is on origin/main, which review-gate checks.
  - AC2's label leaves out "a round not above origin's newest" and "a finding it does not answer".
  - AC3's label leaves out the old prep's raft-folder fallback.
Critique: lesson z-design/spec-design-correspondence ("does every check's label say exactly what its command verifies?").
Consequences: none.
Recommendation: make the message say "number the new round above design-review-<o>.md (z-design 5.4: the round count restarts, the file number does not)", and keep "earlier prep" and the file name, which review-gate pins. Correct the Non-goal's reference. Make each label say what its spec checks, AC2 and AC3 as AC2 and AC3 in the document read.
Lesson: z-design/spec-design-correspondence

### F5 [low] Harvest: design-review-001 F1 was filed as a source of two lessons whose checks do not ask what it found, so its lesson is lost and this round repeats it
Where: `harvest.md`, the line for design-review-001 F1; the reviewer's candidate in design-review-001 (`existence-checks-exclude-earlier-cycles`).
Evidence: the entry names zz-arch/records-cover-what-was-reviewed ("Which files make up the thing this record vouches for, and which commands rewrite them …") and z-design/required-steps-on-every-path ("does something notice if it was skipped?"). `git status` shows no lesson file changed. Neither check asks whether something an earlier cycle of the same item left can satisfy an existence check. That is the defect F1 found, and F1 above finds it again in the mechanism meant to close it. z-design 5.3: "A finding that repeats a lesson the pass should have caught sharpens that lesson's check."
Critique: a source line without a sharpened check is a restated finding, so the next design with an existence check misses the same question.
Consequences: none.
Recommendation: sharpen z-design/required-steps-on-every-path's check with a note, or write the round 1 candidate, adding: "Can what an earlier cycle of this item left satisfy the check: an earlier prep that landed, an earlier scope's rounds still in this worktree, or a round from before the design changed? What tells this cycle's artifact apart?" Harvest this round's F1 to it.

Candidate lessons (reviewer, for the lead to harvest):
- A note on z-design/required-steps-on-every-path (or the round 1 candidate `existence-checks-exclude-earlier-cycles`), from c0161 design review 002 F1. "This prep" was read as "not on origin/main", but a scope reset in place keeps the earlier scope's rounds untracked in the same worktree (c0181), and a closure decided after an approving round has no boundary at all. Check: "Does the proxy for 'this cycle's artifact' tell apart every earlier cycle the skills describe, including the ones that never left the worktree?"
- A note on z-design/reasoned-rows-claim-testable-reasons, from c0161 design review 002 F2. Row L3's reason said the case landed the raft's rounds on origin/main, but the case wrote them in the worktree and committed them locally. The runner's L3 mutated another argument, so it was equivalent and survived. Check: "Does the fixture put the state the reason cites where the reason says (origin/main or the worktree), and does the runner's mutant edit the code the row names?"

Verdict: changes
