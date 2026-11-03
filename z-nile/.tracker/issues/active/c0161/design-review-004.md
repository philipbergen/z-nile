# Review 004: c0161 (design mode)
Inputs: worktree prep-closure-skips-design-review at c199e8de plus its uncommitted item folder (c0161.md, check.sh, acceptance/{review-rule,review-gate,review-raft,design-record,docs}.spec.luau, experiments/{proto-engine,proto-fixtures,proto-skills}.patch, mutants.py, proposed-lessons.md, design-review-001..003, design-refute-001..003, harvest.md, spend.md); `./zn capture c0161` (b473d45c, a confirmed capture: Problem only); the prototype clone (/var/folders/b1/97q05hyx277_zqbc5mcchvlw0000gn/T/tmp.PDPCmUR36g/p: `setStatus`, `keepRecords`, `gitFolderFiles`, `rewriteUnder`, `cmd.renumber`, `cmd.compact`, `cmd.remap`, `READ_ONLY`, `compact.apply`, `ids.rewrite`, the skill diffs); origin/main at f3dc8ff7 (286 commits past c199e8de, none in `z-nile/engine`, `z-nile/tests`, `z-nile/lib` or the skills outside `lessons/`, so the prototype's base is current); c0181.md, c0136, c0178, c0075, c0083, R0061, R0062, R0044, d0124 read from origin/main; `tests/tooling/tracker-guarded.spec.luau`; `./zn lessons --when design` (143 lessons; the full text of the ones named below) and `./zn lessons --skill zz-review --full`. Runs, each on a throwaway copy of the prototype that I deleted afterwards: a probe of `status.designReviewProblem` (F3), three unlisted mutants against `design-record.spec` and the c0116 specs (F1, F2), and `./zn design-record c0161` in two checkouts (F4). The record quote is waived: `./zn design-record` exists only in the prototype, not in this worktree.
Dropped from design-review-003: F1, F2 (the user's "Reviewer-only record" decision; the rule no longer reads refutes, and the cost is in the Design), F3 (the `legacy` branch is gone from proto-engine.patch; L5 is a runner entry; review-raft case 1 refuses a member that has only the raft folder's round), F5 (K7 is in mutants.py, and the grouped case is in design-record.spec), F7 (the zz-review paragraph and z-design 5.2 say "before you read", pinned), F8 (issue-design.spec is in Touched modules; Scalability counts the folders). F4 and F6 are fixed in part; the rest is repeated as F9 and F5.

### F1 [medium] Two of keepRecords' stated behaviours have no case: it reads the work tree, and it re-records issues that were not renamed; both unlisted mutants survive
Where: Design part 4 ("works on the work tree as git sees it (a prep's reviews are not committed until its prep commit)"; "each issue's `Design record:` lines"); Rules and mutants, the K5/K6/K7 row; design-record.spec, "a renumber re-records…" and "a renumbered member keeps…".
Evidence:
- Both renumber cases run `git add -A` and commit before `renumber`, so every file is tracked when keepRecords reads it.
- `renumber` does not refuse a dirty tree (compact and remap call `refuseDirty`; renumber does not). `git mv <dir>` moves untracked files with the folder (I checked in a scratch repository). And `rewriteUnder` rewrites the old id in every root's `.md` and `.sh` files, so the record of any issue whose design names the renamed id changes too.
- Mutant "before-pass reads the index only" (`local files = gitFolderFiles(dir, true)` in the c0161 block): `design-record.spec` gives 9 passed, 0 failed.
- Mutant "only renamed issues" (`… and idMap[iid] ~= nil and …` on the before-pass condition): 9 passed, 0 failed.
- Either mutant leaves the normal prep stale after a renumber: its own reviews are uncommitted, or its Design names an emergent id that gets renumbered. The next `status <id> prepared` then refuses "changed after this round", and the author has to buy one more Opus round for an id change.
Critique: lesson z-design/spec-design-correspondence. The two sentences that decide whether a re-record works in a live prep have no case. The second mutant is the obvious optimisation once Scalability counts 84 folders.
Consequences: none beyond the cases. The untracked case exists only for `renumber`, because compact and remap refuse a dirty tree. Say that in part 4.
Recommendation: add two cases to design-record.spec, each with a Rules and mutants row and a runner entry:
- (a) renumber an issue whose approving round is written after the last commit (untracked), and expect its line re-recorded. Mutant K9: index only.
- (b) a second issue whose document names the renamed id and whose approving round quotes its own record. After the renumber, that issue's line equals its new record. Mutant K10: only renamed issues.
Lesson: z-design/spec-design-correspondence

### F2 [medium] "byte-identical output for the existing `grouped:` hashes; pinned" is not pinned: a `withoutFront` that changes `designHash` survives every spec, and 16 rafts on origin/main carry `grouped:` records
Where: Design part 1 ("It shares one frontmatter filter with `designHash` (`withoutFront`, byte-identical output for the existing `grouped:` hashes; pinned)"); design-record.spec, "keeps raftplan.designHash as it was"; Implementation step 1.
Evidence:
- Every `designHash` assertion is relative. design-record.spec compares a hash with itself after a status, raft or design edit. c0116/plan.spec (lines 262 to 268) does the same. `git grep -n 'designHash\|recordHash' -- z-nile/tests` finds no comparison with a value the old code produced.
- I ran mutant "withoutFront drops the `---` lines" (the `table.insert(kept, line)` removed from the `---` branch), which changes every hash. Results: design-record.spec 9 passed, 0 failed; c0116/plan.spec and c0116/compact-record.spec 22 passed, 0 failed.
- `git grep -l '^grouped: \[' origin/main -- '*/.tracker/rafts/*.md'` lists 16 rafts. With that mutant, `ready` recomputes each member's `recordHash` (main.luau about line 4715) and refuses every one of them as changed since grouped. Each then needs a re-fold and a new coherence review.
Critique: an unpinned refactor of a shared hash is a regression that only shows up later, at someone else's `ready`.
Consequences: the pin is a rule, not a set: existing records stay valid. So it goes in the sequestered spec, which is promoted (zz-review/recommendations-pick-spec-or-check).
Recommendation: add a case to design-record.spec that compares `raftplan.designHash(DOC)` with `string.sub(serde.hash("sha256", EXPECTED), 1, 12)`. `EXPECTED` is DOC with its `status:` and `raft:` lines removed, written out literally in the spec, so the case does not use `withoutFront`. Add a row with mutant K11, "withoutFront changes the kept text", and run it.
Lesson: z-design/spec-design-correspondence

### F3 [medium] A repeated `Verdict:` or `Design record:` line is resolved silently, by two different readers, and the record reader takes the first of two adjacent lines although the Design says the last wins
Where: `status.designReviewProblem` (`string.gmatch("\n" .. review .. "\n", "\nDesign record: (%x+)[ \r]*\n")`); keepRecords' own pattern (`"\nDesign record: (%x+)"`, with no end of line); Design part 3 ("The round's last `Design record: <hash>` line"); rows V3 and Q3; review-rule, "the record is quoted on a line of its own, and the last such line wins".
Evidence: probe of the prototype's status.luau on a scratch copy (record `0123456789ab`):
- `Verdict: approve`, then `Design record: 0123456789ab`, then `Design record: ffffffffffff` on the next line returns nil. A round whose last record line is stale passes.
- The reverse order returns "quotes Design record ffffffffffff, but the design is now 0123456789ab", although the last line is current.
- The pattern consumes the newline it ends on, so the next line's leading `\n` is gone and the adjacent line is skipped.
- The spec's "last wins" case puts a blank line between the two quotes, so Q3 dies there while the shipped code is wrong for adjacent lines.
- `Design record: 0123456789ab (taken before reading)`: the rule says "quotes no … line", while keepRecords counts it and rewrites it.
- No real file needs "last wins". Of the 441 design rounds on origin/main, 0 have more than one line starting `Verdict: ` (`git show` of each, `grep -c '^Verdict: '`). zz-review says a round is never edited, so a second verdict in one round contradicts the format.
Critique: lesson zz-arch/parsers-refuse-ambiguity ("does its parser refuse a repeated or ambiguous field instead of silently keeping one?") and zz-arch/one-reader-per-format. This is the third reading of these lines (rule, keepRecords, docs). The tempting fix is to correct the gmatch and keep "last wins", which still picks one of two hashes the reviewer wrote.
Consequences: with repeats refused, V3 and Q3 change meaning ("a repeat accepted"). keepRecords must read lines through the same function, so it never re-records a line the rule would not read. zz-review's paragraph says "one `Verdict:` line and one `Design record:` line".
Recommendation:
- Add one pure line reader in status.luau, for example `status.roundLines(text) -> (verdict?, record?, problem?)`, that refuses two `Verdict:` or two `Design record:` lines at line start (`<file> has two "Design record:" lines: a round is written once (zz-review)`). Call it from the rule and from keepRecords (main.luau already requires `statusLib`).
- review-rule cases: two adjacent record lines and two verdicts are refused; an annotated record line reads the same in both callers.
- Rewrite rows V3 and Q3, and add a mutant "keepRecords keeps its own pattern".
- Pin the zz-review sentence in docs.spec.
Lesson: zz-arch/parsers-refuse-ambiguity

### F4 [medium] `./zn design-record` hashes whatever checkout it runs in, without saying which, and zz-rules lists it for the main checkout, where a subagent's shell starts; the move then blames the design for a wrong quote
Where: `cmd["design-record"]` (`store.get(id)` in the current checkout); the zz-rules main-checkout list, which gains `design-record <id>`; the zz-review paragraph and z-design 5.2 ("run `./zn design-record <id>`", with no place named); the stale message ("it changed after this round").
Evidence:
- On scratch copies of the prototype, `./zn design-record c0161` printed `815720a6427c` in the prep-like tree and `4e014c2a2bc3` in a clean clone of the same commit. Both runs exit 0 and say nothing about the folder they read.
- A reviewer subagent's Bash cwd resets between calls (the agent notes in this harness say so). This session's own working directory switched to the main checkout mid-run.
- A reviewer who types `./zn design-record <id>` without `cd` hashes main's copy of the issue, not the prep's design. The before and after runs agree, so the zz-review cross-check says nothing.
- The author's `status <id> prepared` then refuses with "changed after this round … needs a new round". The design did not change, but the author pays another Opus round, or is tempted to rewrite the quote (accepted risk 1 made routine).
Critique: lesson z-design/instructions-runnable-where-they-run. The step the whole mechanism rests on can be done wrongly from where the reviewer stands, with no sign of it. A preparing issue's design never lives in the main checkout.
Consequences:
- A refusal in the main checkout moves `design-record` from zz-rules' read-only list to the sentence of commands that refuse there. docs.spec's pin changes, and so does the `c0115/docs` or `c0116/docs` read-only sentence if it names the command.
- Specs run the command in a fixture worktree, which stays allowed.
- The message must not claim a cause it cannot know.
Recommendation:
- Make `design-record` refuse in the main checkout of a repository with an origin, like `new` (`refuseInMainCheckout`), naming the prep worktree command `cd "$(./zn worktree prep-<slug>)"`.
- z-design 5.2 and zz-review say to run it in the prep worktree that holds the design.
- Reword the stale message: "… but the design is now <h2>: it changed after this round, or the round quoted another checkout's design; run a new round".
- design-record.spec: the fixture's main checkout refuses, the worktree prints. Add a row with mutant "the refusal removed".
Lesson: z-design/instructions-runnable-where-they-run

### F5 [medium] (repeat of design-review-003 F6, in part) "outputs written after the final round go to `.cache/`" is only in c0161's own Design; no skill tells a prep, and preps write logs into `experiments/`
Where: Design part 1 (the last sentence); proto-skills.patch (no such sentence in z-design, zz-review or zz-rules: `grep -n experiments` over the five skills finds only the existing lines and the new zz-rules row); experiments/proposed-lessons.md.
Evidence:
- `origin/main:z-nile/.tracker/issues/c0083/experiments/mutants.log` is a mutation log kept in `experiments/`. Under this rule, a log like that written after the final round stales the record, and the refusal reads "changed after this round".
- c0161's own `experiments/proposed-lessons.md` is text "for the lead to write". If the lead edits or removes it after the final round, while harvesting, c0161 itself is refused.
- design-review-003 F6's recommendation was "decide which, and write it in z-design and zz-review". The refute says "stated in the Design".
Critique: every other prep learns the rule from a refusal. A refusal costs an Opus round, which the user has said is expensive.
Consequences: zz-execute (line 21) keeps writing experiment results into `experiments/` during execution. That happens after `prepared`, so it is harmless; say so, so nobody "fixes" it.
Recommendation:
- Add to z-design (step 4 and 5.5) and zz-review's paragraph: "everything under `experiments/` is part of the design record: a log or note written after a round goes to `.cache/` or outside the item folder". Pin it in docs.spec.
- Move `proposed-lessons.md` out of `experiments/` (for example into the item folder's top level, which the record does not cover) before the final round.
Lesson: zz-arch/records-cover-what-was-reviewed

### F6 [medium] A round 5 that says `changes` "goes to the user", but nothing says what the user can decide, and the engine accepts nothing but a newer approving round, which the 5-round cap forbids
Where: z-design 5.4 ("Rounds: up to 5 rounds"; "round 5, which is always final"; "a round 5 that says `changes`, or holds a high, goes to the user, whatever you answered to it"); 5.5 ("a final round that says `changes`, which only round 5 can be, goes to the user instead"); `designReviewProblem`.
Evidence:
- Under the old rule, the user's usual answer was to accept the answered round 5. review-rule's "a round that says changes is never the last: a refute beside it … does not stand in" pins that no refute, and no line in one, lets a `changes` round through.
- So after round 5 says `changes`, `status <id> prepared` refuses, whatever the user decides, until a `design-review-006.md` approves. The skills cap rounds at 5 and offer no way to lift the cap.
- c0161 is on round 4 itself.
- Round 3 F1's Consequences named this ("A user-decided round 5 needs a way through"), and neither the Design nor the refute answers it.
Critique: lesson z-design/required-steps-on-every-path, the path through the user. A lead who follows the skills is stuck, or edits `status:` by hand (allowed only offline).
Consequences: no engine change. The rule already demands an approving round, so the way through is a round past the cap, by the user's decision. Round metrics already read any number.
Recommendation:
- Write the user's options into z-design 5.4 and 5.5: "the user decides: another round past the cap (recorded as `Decided with the user (YYYY-MM-DD)` in Unknowns & experiments), a scope decision, or giving the issue back (`status <id> new`); the engine prepares nothing on a `changes` round".
- Pin the sentence in docs.spec.
- Add a review-gate case: rounds 001 to 005 with 005 `changes` are refused, and a 006 that approves with the record passes.
Lesson: z-design/required-steps-on-every-path

### F7 [medium] The accepted risks and the audit Non-goal leave out two ways past the rule, and cite the wrong risk number; the user decided the audit on that list
Where: Non-goals, the audit bullet ("The residual paths it would have caught are the three in accepted risk 3 (an engine that predates this rule, a garbled `status:` line, `release`)"); Accepted risks 1 to 4.
Evidence:
- **The wrong number.** Those three paths are accepted risk 2. Risk 3 is the hand edit made offline.
- **An edit after the move.** `git grep -n designReviewProblem -- z-nile/engine` finds one call, in `setStatus`. After `status <id> prepared`, z-design 6 commits, and Landing a change runs `./zn sync`, the gate, push, PR and merge. Nothing reads the record again. A fix to the item's own spec after a gate failure, a Design sentence added while answering a PR comment, or a conflict resolved in the document lands `prepared` with a stale quote. The audit option as described ("any backlog issue effectively `prepared` with no round that quotes its design") would catch this path, which the Non-goal's list omits.
- **A removed round.** A prep's rounds are untracked until the prep commit. Deleting a newest `design-review-002.md` that says `changes` makes an older approving round the newest. If the design did not change since, the move passes, and git keeps no trace. spend.md's `--note design-review-002` row shows the gap, but nothing reads it.
Critique: lesson z-design/accepted-risks-checked-and-decided. The Non-goal's stated reason is wrong (the number) and incomplete (the post-move path), and the user weighed the audit against it.
Consequences: correcting the list may change the user's answer. That is the user's call, not a cut or an addition by the author.
Recommendation: rewrite accepted risk 2 with the post-move edit, and accepted risk 1 with the removed round, each with its checkable premise (the single call site; untracked rounds). Fix the Non-goal's reference. Then escalate to the user: relay the corrected list with the options and their costs:
- (a) keep the decision on the corrected premise;
- (b) the audit as already described (about 40 lines, exemptions c0075, c0083, c0136, c0178, c0181);
- (c) a cheaper check where a prepared issue is next read (`new raft`, `fold`, `ready`), comparing its newest round's quote with its record on origin/main, with the same exemptions.
Lesson: z-design/accepted-risks-checked-and-decided

### F8 [low] Restated wording disagrees with the mechanism in six places
Where and evidence:
- The pinned `ROUND` string in docs.spec, z-design 5.5 and zz-rules says the newest round "ends `Verdict: approve`". The format now puts `Design record: <hash>` after the verdict, and the rule reads the last `Verdict:` line, not the file's end.
- The `cmd["design-record"]` comment in proto-engine.patch says the hash is the one "an author quotes when answering a `changes` round". That contradicts "Reviewer-only record".
- The zz-rules command row says "A reviewer who approves quotes it". z-design 5.2 and zz-review have every design round quote it.
- The stale message cites "z-design 5.4" for "a Design changed after a round … needs a new round". That sentence is a 5.3 bullet.
- z-raft §5 says "a `preparing` member **of the old prep**". The rule applies to every `preparing` member, including one claimed here (review-raft case 3).
- zz-review's format block shows `Design record: <hash>` for every mode. Code-mode and raft-mode reviewers have no record (`design-record R0010` refuses).
Critique: lesson z-design/restated-rules-move-together.
Consequences: the docs.spec pins change with the wording.
Recommendation: reword each one, for example "its newest `design-review-NNN.md` says `Verdict: approve` and quotes …", and "(design mode, for an issue)" beside the format line. Update the pins.

### F9 [low] (repeat of design-review-003 F4, in part) The "one file-set function" decision for c0181's proof stamp has no carrier to c0181's execution
Where: Shared state, the c0181 bullet ("c0181's design has no mention of c0161 yet; the lead sends this to c0181's execution"); `raftplan.recordPaths(…, specsOnly)`.
Evidence: c0181 is `prepared-otter-heron-mongoose` on origin/main with no raft. Its executor reads its own document and the prompt z-ready builds from its raft. `grep -n c0161` over origin/main's c0181.md finds nothing. A message "sent" by the lead lands nowhere an executor reads. Until then, `specsOnly` is a parameter with no caller outside a spec.
Critique: lesson z-design/results-land-on-every-path.
Consequences: none for c0161's own behaviour.
Recommendation: name the carrier, for example "when c0181 is rafted, z-raft's Theme quotes this decision", or a capture (`./zn new issue c …`) for the lead. Or drop the promise and keep `specsOnly` as c0161's own documented API.

### F10 [low] Two numbers don't match the tree
Where and evidence:
- `size: 330`. The prototype the executor applies is `git diff --numstat` +182 / -11 (engine 156 added, skills 16, the five promoted fixtures 11), about 193 changed lines.
- Existing work says "about 26 are `preparing`" and "25 `preparing` issues". `git grep -l -E '^status: preparing' origin/main -- '*/.tracker/issues/*.md' '*/.tracker/rafts/*.md'` lists 17 today (16 issues and R0062).
Critique: lesson z-design/touched-paths-exist (claims about the tree are rechecked each round).
Consequences: none.
Recommendation: set `size:` from the prototype's numstat plus the F1 to F6 additions. Requote the count with its search and date.

Candidate lessons (reviewer, for the lead to harvest):
- A note on zz-arch/parsers-refuse-ambiguity, from c0161 design review 004 F3. A `gmatch` over `"\n…\n"` whose pattern ends in `\n` consumes the newline the next line starts with, so it never sees an adjacent repeat. And "last wins" for a line its writer writes once silently keeps one of two values. Check: "Does this line reader see two adjacent matching lines, and does it refuse the repeat?"
- A note on z-design/spec-design-correspondence, from c0161 design review 004 F2. A refactor claimed to keep a hash's output "byte-identical" needs a case that compares with a value computed without the new code. Relative cases (same input, same hash) pass for any filter. Check: "Is every 'unchanged output' claim pinned against a value the old code, or an independent computation, produced?"
- A note on z-design/instructions-runnable-where-they-run, from c0161 design review 004 F4. A subagent's shell starts in the main checkout, so a command whose answer depends on the checkout either refuses there or names the folder it read. Check: "Run where a subagent's shell starts, does this command give the answer for the tree the instruction means?"

Verdict: changes
