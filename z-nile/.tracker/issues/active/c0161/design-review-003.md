# Review 003: c0161 (design mode)
Inputs: worktree prep-closure-skips-design-review at c199e8de plus its uncommitted item folder (c0161.md, check.sh, acceptance/{review-rule,review-gate,review-raft,design-record,docs}.spec.luau, experiments/{proto-engine,proto-fixtures,proto-skills}.patch, mutants.py, proposed-lessons.md, design-review-001/002.md, design-refute-001/002.md, harvest.md); `./zn capture c0161` (Problem only; the Problem now also holds the user's `Decided with the user (2026-11-01): "Design record"` line); `z-nile/engine/{main,status,raftplan}.luau` (`setStatus`, `keepRecords`, `gitFolderFiles`, `cmd.new`'s `new raft`, `fold`, `refuseUnraftable`, `rewriteUnder`, `cmd.remap`, `cmd.compact`, `READ_ONLY`, `flags`); origin/main as fetched this round (228 commits past c199e8de, none in `z-nile/engine`, `z-nile/tests` or the five skills apart from `lessons/`); R0044 and d0124 history on origin/main; `git worktree list` and the documents of c0181 (`prep-lessons-codify-consolidate` at 70fa9f21), c0178 (`prep-shared-fixture-images`) and c0136 (origin/main); a probe of the prototype's `status.luau` on a scratch copy (`lune run probe.luau`, output quoted in F1); searches over origin/main pasted in F2, F3 and F8; `./zn lessons --when design --full` and `./zn lessons --skill zz-review --full`.
Dropped from design-review-002: F1 (answered by the user's "Design record" decision; the origin comparison and its false c0181 sentences are gone; what the record leaves open is F1 and F3 below), F2 (fixed: L3 removed, a member's own round decides with the record; the fallback that remains is F3 below), F3 (fixed: both twins named, and the `### F1: claim` / `### F10 [low]` case is in review-rule; the refutation of a shared reader is right), F4 (fixed), F5 (fixed in harvest.md; the sharpened lesson text waits in experiments/proposed-lessons.md for the lead).

### F1 [high] (repeat of design-review-002 F1, in the new mechanism) On a `changes` round the record is written by the author, so a closure written while answering the round, or a reset scope with one line added to an old refute, passes with no round that read it
Where: Design part 2 (the refute has the last word when the review says `Verdict: changes`); part 3, "The record" ("So a reclaimed prepared issue …, a scope reset in place …, and a reviewed fix design rewritten into "No code change" all meet the refusal"); Chore checklist, Existing work ("A `changes` round is fixed by the author adding the refute's line"); Accepted risk 1.
Evidence:
- I ran the prototype's `status.designReviewProblem` (a scratch copy of `z-nile/engine/status.luau`):
  - Case 1. `design-review-001.md` is `### F1 [high] the fix is wrong` / `Verdict: changes` / `Design record: aaaaaaaaaaaa` (the fix design the reviewer read). `design-refute-001.md` is `- F1: fixed: the user retested, no code change now` / `Design record: bbbbbbbbbbbb`. The record now is `bbbbbbbbbbbb`. Output: `closure written while answering a high: nil`.
  - Case 2. `design-review-005.md` is `Verdict: changes` (an earlier scope). `design-refute-005.md` is answered, with one appended `Design record: cccccccccccc`, the current record. Output: `reset in place, one line appended to an old refute: nil`.
- Case 1 is round 2 F1's case, a reviewed fix design rewritten into a closure. It passes whenever the last round said `changes`, and that is the usual verdict of a first round: this issue's rounds 1 and 2, and 41 of the 84 newest rounds on origin/main (E3).
- Case 2 is the reset in place the record "exists for" (c0181's route). Existing work prescribes the same appended line as the remedy for in-flight preps.
- z-design 5.4 requires another round in both cases: a high was fixed after round 1, and the answer was more than minor. The engine does not see that, and the Non-goals leave "the round rule of z-design 5.4" to the author.
- So on this path the engine adds nothing to today's skills, while the Design says these cases "all meet the refusal". Accepted risk 1 names a forged review and a lazy reviewer, but not the author's own refute.
Critique: a record proves what its writer saw. In a `changes` round the writer is the author, the party the rule exists to check (d0151's closure was an author's). This is the third hole in "which round covers this design": round 1, an earlier cycle; round 2, a reset in place; now, the author's record. The tempting fix is a z-design 5.3 sentence ("the refute's record may only cover answers"). The engine can't check that either.
Consequences:
- Only a record a reviewer wrote proves a reviewer read the design. Holding to that means the final round must be an approving round whose record still matches, which collides with how approving rounds are answered today (F2).
- Any relief for F2 that gives the author's refute the last word on an approving round reopens this hole there too.
- A middle way the engine can check is z-design 5.4's own high rule. A `### F<n> [high]` heading in the newest round means it is not final ("run another round if any high finding was fixed or refuted"; a round 5 with a high goes to the user). That closes case 1 for highs and case 2 when the old round had a high. It leaves open an answer to a round with only medium findings. A user-decided round 5 needs a way through, such as a `Decided with the user (YYYY-MM-DD)` line in its refute.
Recommendation: escalate to the user, as one question together with F2. The decision covers "after an approving round" and is silent on `changes` rounds. Options:
- (a) **Reviewer-only record.** The newest round must be `approve` and quote the current record; answering any round's findings by an edit needs a new round. This closes F1 and F2's hole. Cost: one more Opus round in most preps (F2's 33 of 44, plus most of the 41 of 84 that end on `changes`), and z-design 5.4 and 5.5 rewritten.
- (b) **The author vouches, plus the 5.4 high rule in the engine.** A newest round with a `[high]` heading is refused unless its refute carries a `Decided with the user` line. About 15 lines. Review-rule cases: a high answered `fixed` in the newest round is refused; an answered medium-only `changes` round passes; a round-5 high with the line passes. Mutant: "high headings ignored". Accepted risk: a medium-only round answered with a rewrite passes.
- (c) **The author vouches, as now.** The accepted risk is written on its true premise (cases 1 and 2 above), with a `Decided with the user` line.

Whichever is chosen:
- Correct the "all meet the refusal" sentence, Existing work's remedy and accepted risk 1.
- Add a review-rule case that pins the chosen behaviour on the `changes` path. Today no case fails for a closure written in the refute.
Lesson: z-design/required-steps-on-every-path

### F2 [high] The usual answer to an approving round, fixing its findings, now fails the move: 33 of the 44 newest approving rounds on origin/main were followed by `fixed` answers, and each changed the design the reviewer quoted
Where: Design part 2 (for `approve` the review has the last word; "approve needs nothing beside it"); z-design 5.3 as edited ("Answer every finding … Fix it in the documents" stays); Existing work; Usability ("A reviewer's and an author's extra step is one command … and one line").
Evidence:
- The search, over every folder on origin/main: take its highest `design-review-NNN.md`; when that round says `^Verdict: approve`, look for `^### F` and a same-numbered refute.
  `for d in $(git ls-tree -r --name-only origin/main | grep -E '/design-review-[0-9]{3}\.md$' | xargs -n1 dirname | sort -u); do n=…newest…; …; done`
  Result: 44 approving newest rounds; 34 carry findings; 33 of those have a `design-refute-NNN.md`; all 33 refutes contain `fixed`.
- With the prototype, each of those flows is refused at `status <id> prepared`. The fix changes `{id}.md`, `check.sh` or a spec, so the record differs from the review's line ("… quotes Design record <h>, but the design is now <h2> …"). For `approve`, the engine does not read the refute.
- No review-rule or review-gate case has an approving round whose findings are answered by a fix. review-gate's "a design changed after its approving round" pins this refusal without naming it as the normal flow.
Critique: the user decided that "any change to the design after an approving round needs a new round". The cost was not in the relayed options: about three in four approving final rounds are followed by edits. Unstated, the rule turns most approvals into one more Opus round. Otherwise it teaches authors either to leave findings unfixed, against 5.3, or to rerun `./zn design-record` and patch the reviewer's line, which is accepted risk 1's forgery made routine.
Consequences: either the cost is accepted and written down, or the refute gets the last word on approving rounds too, which is F1's hole. Written down means z-design 5.3 says that a final approving round's findings are answered without editing the design (refuted, or carried into execution in the refute), or by a new round.
Recommendation: put these numbers to the user in F1's question. Under (a) this is the rule. Under (b) or (c), say whether a refute beside an approving round takes the last word. Then write the answer, with the measured cost, into z-design 5.3 and 5.4, zz-review's paragraph, Existing work and Usability. Add a review-rule case for an approving round with a refute, either way, and a docs.spec pin for the sentence.
Lesson: z-design/new-rules-migrate-existing-work

### F3 [high] The record-free fallback for "the old prep" now serves no item, but `new raft` over `new` issues still takes it, so a new raft's members are prepared on a raft-folder round that quotes no record
Where: Design part 3, second call bullet; Existing work (the R0044 sentence); `proto-engine.patch`, the `legacy` block of `setStatus`; review-raft cases 3 to 5; rows L1, L2, L4; the fixture edits for commands-prep `{zeta}`, commands-start `R0001` and claims `c0025`.
Evidence:
- **R0044 is not `preparing` any more.**
  - `git show e07144ab` ("tracker: release R0044", 2026-11-01 11:06) changes `status: preparing-sunny-falcon-sunny` to `prepared-…` for both R0044 and d0124.
  - `c6b347cb` ("tracker: ready R0044") moved both to `active/`: `origin/main:pickman/.tracker/rafts/active/R0044/R0044.md` has `status: active-walrus-falcon-mongoose`.
  - A later `stop` brings it back prepared, and the loop's `continue` takes a prepared member as it is.
  - So the Existing work sentence is false today, and the fallback has no live user.
- **No other item needs it.** The search `git grep -l -E '^status: preparing' origin/main -- '*/.tracker/issues/*.md' '*/.tracker/rafts/*.md'`, with each hit's `raft:` line, finds 25 `preparing` issues, none with a `raft:` value. The only `preparing` raft is R0062, whose members c0139 and c0141 are `prepared-…`. No member on origin/main carries a raft's stamp.
- **New work can still take the route.**
  - `new raft` takes members that are "all `new` (the old prep: each is claimed with the raft's stamp)" (main.luau, the comment in `cmd.new` above `kinds`), and zz-rules documents it: "`new raft` (claims the raft, and its members when they are `new`)".
  - review-raft's case 3 is that route: `new raft chore old-prep <new issue>`, a `design-review-001.md` with no record in the raft's folder, and the member passes.
  - So a closure designed in the member's folder after the raft's round passes, then and after any later edit, because the record is never asked for. That is the captured Problem on a route the engine supports.
Critique: the fallback was kept so that R0044 would not need a sixth review (round 1 F2), and that reason expired today. What remains is an exemption from the user's decided record for every raft made the old way. The tempting fix is to keep it "in case" with a sentence. Lesson z-design/fallbacks-name-the-modes-they-cover asks which modes take a fallback and whether the Problem is solved in each. Here it is not.
Consequences: without the fallback, every non-raft target is judged by its own folder, with the record.
- The old prep then needs a round with a record in the member's own folder. It already needs one when the member has any round of its own.
- The fixture edits in commands-prep, commands-start and claims put the round in the member's folder with `design-record`, as commands-claim's edit does.
- Rows L1, L2 and L4 go, and the "member claimed here" case stays.
- No captured outcome narrows.
Recommendation: remove the `legacy` branch.
- Rewrite Existing work with the two searches above, pasted, and R0044's history.
- Add a review-raft case: `new raft` over a `new` issue, with an approving round only in the raft's folder, is refused naming the member and `design-review-001.md`; with the member's own round quoting its record, it passes.
- Add mutant L5, "the raft's folder stands in when the member has no round" (the prototype's behaviour), killed by that case.
- Rerun E2 for the changed fixtures.
Lesson: z-design/fallbacks-name-the-modes-they-cover

### F4 [medium] Shared state is a round behind: c0181 was prepared by the old engine without the hand-off, and its proof stamp is a second design record at the same move
Where: Chore checklist, Shared state (the c0136, c0181 and c0178 bullets); Existing work (the c0181 sentence).
Evidence, from `git worktree list` and each item's own documents this round:
- **c0181** (`prep-lessons-codify-consolidate` at 70fa9f21 "tracker: prep c0181 …") is `design: ready` and `status: prepared-otter-heron-mongoose`, with a clean tree. Rounds 001 to 010 are committed, and 010 says `Verdict: changes`. So the Design's sentence ("its earlier scope's rounds 001 to 005 only untracked … it is refused until a round that quotes its design exists") is false. The engine without this rule prepared it, which is accepted risk 2's path, and it will land that way.
- **The hand-off is missing.** `grep -n c0161 z-nile/.tracker/issues/c0181/c0181.md` finds nothing, so "c0181's prep must list it among the command's existing refusals" is not in c0181's design. Its Order sentence (c0181.md:113) is generic: "`rules.enforce(hook, view)` runs after the command's existing refusals and before its first write after them".
- **c0181's proof stamp is a second record of "the design as it is" at the same move.** c0181 reads a proof stamp at `prepared`:
  - c0181.md:29: "with the stamp checked at the move to prepared";
  - c0181.md:285: "goes stale on a spec byte, check.sh or the prototype";
  - c0181.md:281: "a rename keeps a proof fresh".
  Its file set differs from this record's (it covers the prototype; the record leaves out `experiments/`), and it has its own rename handling beside `keepRecords`.
- **c0136** is `prepared-brisk-crimson-pink` on origin/main: its prep landed.
- **c0178** is `prepared-jolly-walrus-mellow` in `prep-shared-fixture-images` and keeps `f.other` as a field through `fixture.defer` (c0178.md:111), so the specs' `elsewhere` stays valid.
Critique: lesson z-design/quote-other-preps-before-promising: rerun the search each round, and quote the current status and outcome. Two records of one design, checked at one move, each with its own file list and re-record step, are the drift that zz-arch/one-reader-per-format warns of.
Consequences:
- Whichever of c0161 and c0181 lands second has to place its refusal relative to the other's, and both file lists have to stay in step.
- c0161's fixtures prepare stub issues, so c0181's `prepared` rules must not refuse them first. Its presence rules judge only a document with a Rules and mutants data row (c0181.md:111); for its absence rules, that is not shown.
Recommendation:
- Requote c0136, c0178, c0181 and R0061 from their current documents.
- Name c0181's proof stamp, and decide with the lead and c0181's prep: either one shared function for "the files a design is made of", which both records call (any difference a declared parameter with its reason), or a stated reason why they differ.
- State the order of the two refusals at `prepared` in both designs.
- Run c0161's sequestered specs on a tree that holds c0181's prototype, and record the result (lesson zz-review/claims-cite-a-prototype-holding-the-files).
- Rewrite the c0181 sentence in Existing work: c0181 is an example of accepted risk 2, not of the refusal.
Lesson: z-design/quote-other-preps-before-promising

### F5 [medium] The re-record changes a grouped member's `recordHash`, and no case pins that `grouped:` follows it
Where: `proto-engine.patch`, `keepRecords` (the new step runs before the `kept` loop); design-record.spec, "a renumber re-records …"; rows K5 and K6.
Evidence:
- `raftplan.recordHash` hashes a member's `design-review-*.md` and `design-refute-*.md` (`isDesignFile`).
- The new step rewrites a prepared member's `Design record:` line. The `kept` loop then recomputes `recordHash` (`gitFolderFiles(mdir, true)` lists the index but reads the bytes from disk) and rewrites `grouped:` and `Grouped:`.
- That is right only because the new step runs first. Moved after the `kept` loop, which is a plausible refactor ("re-record last"), every grouped member whose review quotes its record keeps a `grouped:` entry that no longer matches its files. The carried move's `regrouped` check then refuses the raft as "changed on origin/main since … grouped it".
- The only re-record case renumbers an issue in no raft. `grep -n -i "grouped\|compact\|remap" acceptance/*.luau` finds only a review-raft case title.
Critique: an order dependence with no case, and a plausible mutant that no row lists (design mode item 0; lesson z-design/spec-design-correspondence).
Consequences: none beyond the case.
Recommendation:
- Add a design-record case. A prepared member is grouped into a raft whose coherence review quotes `Grouped:`, and the member's own review quotes its record. Renumber it, then assert:
  - the member's line is re-recorded;
  - the raft's `grouped:` entry and its review's `Grouped:` line equal the member's new `recordHash`.
- Add mutant K7, "the new step moved after the `kept` loop", killed by that case, and run it.
Lesson: z-design/spec-design-correspondence

### F6 [medium] The record leaves out `experiments/`, yet the Implementation steps tell the executor to apply the prototype patches kept there
Where: Design part 1 (the record's files: "Not … `experiments/`"); E1 ("to be applied with `git apply` at the start of execution"); Implementation steps 1 ("the text of `experiments/proto-engine.patch`"), 3 and 4.
Evidence: after an approving round, an edit to `experiments/proto-engine.patch`, such as dropping the `keepRecords` hunk, leaves `./zn design-record c0161` unchanged. design-record.spec pins `experiments/e.luau` as ignored. The move passes, and the executor applies code that no reviewer read. The same holds for any prep whose steps say "apply the prototype". c0181's proof stamp, by contrast, goes stale "on … the prototype" (F4).
Critique: lesson zz-arch/records-cover-what-was-reviewed ("which files make up the thing this record vouches for"). `isDesignFile`'s reason for leaving `experiments/` out ("change for other reasons") was written for the grouped record. For this record, part of what was reviewed is the prototype. The tempting fix is to include all of `experiments/`. That makes the record stale whenever a mutation run writes a log there after the final round.
Consequences: one of two rules must be written down:
- the record includes the experiments files, and the skills say outputs written after the final round go to `.cache/`, not the item folder; or
- the record excludes them, and the skills say the Implementation steps never hand the executor a file outside the record (the Design quotes it instead).
Recommendation: decide which, and write it in z-design and zz-review. Add a design-record case for the chosen side: either an edit to `experiments/proto.patch` changes the record, or a docs.spec pin of the rule. Give it a mutant. Settle it together with c0181's stamp (F4).
Lesson: zz-arch/records-cover-what-was-reviewed

### F7 [low] The reviewer takes the record after reading, so an edit made during the round is recorded as read
Where: the zz-review paragraph in `proto-skills.patch` ("run after you finish reading"); z-design 5.2.
Evidence: a lead who keeps working in the folder while the reviewer reads (the user asks for parallel work) changes the design mid-round. The reviewer's final `./zn design-record` hashes the edited design, and the move passes on a round that read the earlier text.
Critique: what a round can vouch for is what was there when the reading started.
Consequences: none.
Recommendation: tell the reviewer to run `./zn design-record <id>` before reading and quote that hash. If a second run at the end differs, the reviewer says so under Inputs, and the stale record makes the engine ask for a new round. Pin the sentence in docs.spec.

### F8 [low] Two statements don't match the tree
Where: Touched modules; Scalability.
Evidence:
- Touched modules lists four promoted specs. Overrides, AC5, `check.sh` and `proto-fixtures.patch` edit a fifth, `z-nile/tests/acceptance/c0116/issue-design.spec.luau`. The engine reads Touched modules for overlap (main.luau:3421).
- Scalability says `keepRecords` "adds one pass over the issue folders it already scans".
  - Today it lists their paths (`audit.scan`) and reads only grouped members' folders.
  - The new step runs `git ls-files` in, and reads every file of, each issue folder: 212 on origin/main (`git ls-tree -r --name-only origin/main | grep -cE '/\.tracker/issues/(active/|done/|retired/)?[cdf][0-9]{4}/[cdf][0-9]{4}\.md$'`).
  - It does this on every `renumber`, and twice per `remap` (the branch and the scratch base).
Critique: lesson z-design/touched-paths-exist; and the user weighs CPU cost.
Consequences: none.
Recommendation: add the fifth path to Touched modules. Restate Scalability with that count, or call `gitFolderFiles` only for folders whose listing holds a `design-review-` or `design-refute-` file.

Candidate lessons (reviewer, for the lead to harvest):
- A note on the proposed z-design/existence-checks-exclude-earlier-cycles (experiments/proposed-lessons.md), from c0161 design review 003 F1. Its "How to apply" prefers "an artifact that names what it was made for (a hash of the design it read)". A hash vouches only for what its writer saw, and here the author wrote it for `changes` rounds. Check: "Who writes the record this check trusts, and is it someone other than the party whose change the check exists to catch?"
- A note on z-design/new-rules-migrate-existing-work, from c0161 design review 003 F2. "Existing work" means the normal flow's own artifacts as well as old items: measure how often the step the rule constrains happens today (here, 33 of 44 approving rounds were followed by fixes) before calling the new step "one line". Check: "On the last N real runs of this step, how many would the new rule refuse or make cost more, and is that number in the design and in the user's decision?"

Verdict: changes
