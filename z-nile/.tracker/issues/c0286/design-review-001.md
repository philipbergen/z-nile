# Review NNN: c0286 (design mode)
Inputs: prep worktree `prep-raft-plan-keeps-tied-issues-together` at e29589b3 with the uncommitted `c0286.md`, `check.sh`, `acceptance/{ties,plan-cli,docs}.spec.luau`, `experiments/{proto.patch,mutants.py}`; origin/main 1c751733c (fetched for this review); the prototype worktree `proto-c0286` at e92389cc. Spot-run on the prototype, in the environment check.sh's `undispatched` uses, through `./zn run`: `ties.spec` 13/13 and `docs.spec` 4/4 pass. AC4's `family()` was run read-only on this tree. Also read: `raftplan.luau`, `cmd["raft-plan"]`, `dispatch.next` and `dispatcher.facts`, c0161's and c0250's prototypes, R0093 on origin/main, and the c0248 family's documents.

### F1 [high] The existing-work checklist is out of date on its own base and on origin/main, and it misses the family the user tied to R0093 on 2026-11-15
Where: c0286.md Behaviour 6 (the c0248 bullet and the paragraph after it), Touched modules, Implementation step 5, check.sh AC4.
Evidence:
- The document says "c0248 and c0250 are prepared and in R0093 (with c0247 and c0256 …; R0093 `preparing`)" and "(today c0249, c0251, c0252, c0253 and c0254)". On the prep base e29589b3, R0093 is `issues: [c0256]` and c0248 and c0250 have an empty `raft:`. On origin/main, 979dc94ae (#428, 2026-11-15 10:43 PST) unfolded both (`raft: R0093` became `raft: `), and R0093 is `issues: [c0256, c0247]`, `prepared`. So step 5 will write `c0248.md` and `c0250.md` as well. AC4 run on this tree already demands it: `c0248's tied: () does not name c0249`. But Touched modules lists neither file. And "then folds them into R0093 if it is still open" cannot happen: R0093 holds no member of the tie, so Behaviour 3 makes the tie a `new` raft, apart from R0093.
- R0093's Theme on origin/main records: User decision (2026-11-15), "Redesign as stacks (Recommended)": "c0260, c0248, c0262 and c0250 went back to z-design and rejoin this raft when redesigned as layers of one raft". The same section quotes "Logically keep your PRs together it's fine". This ties c0260, c0248, c0262 and c0250 to R0093's c0256 and c0247. Behaviour 6 searched only issue documents, with phrases that do not include "rejoin" or "keep … together", so it missed this family. On origin/main, c0260 (size 1860), c0262 (750), c0248 (1600) and c0250 (2200) are all `prepared`, `design: ready` and raftless. With lines on c0248 to c0254 only, c0260 is in no tie: `raft-plan` makes it a `single` raft by itself (it is over the cap), and c0262 is placed by the chore rules apart from R0093. That is the capture's defect: "an issue the user tied to others" rafted without them.
Critique: the capture states a rule for the real tree, and the migration is what makes the rule hold for ties already decided. The tempting fix is to add the two documents to Touched modules and correct the narrative. That leaves the R0093 family unprotected.
Consequences: the two recorded decisions share c0248 and c0250. "Keep one raft" (c0248 to c0254) plus "rejoin this raft" (c0248, c0250, c0260, c0262 with c0256 and c0247) make one tie of eleven issues. That tie folds into R0093 only while R0093 is open and prepared. `ready` does not read `tied:`, so R0093 (c0256, c0247) can be readied before c0249 and c0251 to c0254 (all `new`) are prepared. After that the tie stops at cause 6 for good, and z-raft with arguments decides. The records do not settle whether the user meant one eleven-issue raft, with R0093 waiting for five unprepared issues, or two stacks; that is a product decision. The facts in Behaviour 6 also moved twice today (6dab4d9f4 and 979dc94ae), so they will move again before execution.
Recommendation:
- Re-derive Behaviour 6 on the current origin/main. Search raft documents too (the Theme's "User decision" lines, `design-refute-*.md` rulings), and add "rejoin", "stack them" and "keep … together" to the phrases. Name the R0093 family and quote its decision.
- Ask the user, through `questions.md`, which issues the tie holds: the union {c0247, c0248 to c0254, c0256, c0260, c0262} folding into R0093, or a named subset. Record the answer as a `Decided with the user` line.
- Under that answer, make step 5's id list, AC4's families and Touched modules cover every document step 5 may write (`c0248.md`, `c0250.md`, `c0260.md` and `c0262.md` included).
- Word each member's state as a condition at the raft's base ("a member in the backlog with no raft gets …, a member in an open raft …"), not as "today".
- Add a ties.spec case for that shape: some members in an open raft beside untied members, the rest raftless and some not prepared, gives a skip naming the waiting members; once all are prepared it gives `fold R… <the rest>`.
Lesson: z-design/new-rules-migrate-existing-work; z-design/design-the-execution-window

### F2 [high] AC4 passes a migration that writes a tie `raft-plan` cannot read, or the wrong tie
Where: check.sh `family()` and AC4.
Evidence: `[[ $tied == *"$other"* ]]` is a substring test over whatever `sed -n 's/^tied: *//p'` prints. It passes for:
- `tied: c0248 c0250 c0251 c0252 c0253 c0254`, which has no brackets (`parseTied`: `tied: is not a list of issue ids`);
- `[c0248, c0250, c0250, …]` (refused: `names c0250 twice`);
- a line that also names c0263, which joins the c0263 family to the tie, so cause 6 ("R0099 … is active, active") applies to it for good;
- two `tied:` lines;
- a line anywhere in the front matter, or a document also edited elsewhere (step 5: "Touch nothing else").

A malformed line on a member that is not a candidate is also silent. Behaviour 1 reports a `tied:` problem only for a candidate, and "its own line adds no edges". If every migrated line is malformed, the tie is gone and the first member prepared is rafted alone, which is the defect this chore fixes, while AC4 stays green.
Critique: the tempting fix is a stricter bash regex.
Consequences: a regex in bash is a second reader of the format (lesson zz-arch/one-reader-per-format), and the silent case stays open for any line written by hand later.
Recommendation:
- Make AC4 a spec, `acceptance/family.spec.luau`, that reads the real tree with plain reads as `docs.spec` does. For each member step 5 must write, it requires exactly one `tied:` line, at the place step 5 puts it. It parses the line with `raftplan.parseTied` and requires no problem. It compares the list with exactly the other members that the step-5 rule names, sorted. It also requires that the union of all the lines in the tree makes each family one connected group naming no id outside the family.
- Add Rules-and-mutants rows for a malformed line, an extra id and a missing member.
- Close the silent case: `raft-plan` names an unreadable `tied:` on any backlog issue, candidate or not (`skip <id>: tied: …`). Add a ties.spec case: a `new` issue with `tied: c0001` beside a prepared c0001 prints that skip for the new issue. The zz-rules row says a skip may name an issue that is not prepared yet.
Lesson: zz-arch/one-reader-per-format

### F3 [medium] The tie verdict decides candidates with its own test, which disagrees with c0161's stale skip; c0161's design record also reads the new line
Where: Behaviour 6, "Other work in flight"; proto.patch, `verdict`: `if isCandidate(m) and m.size ~= nil and not tiedProblem[id]`.
Evidence:
- c0161 (`design: ready`) adds `stale: string?` to `raftplan.Issue`, skips a stale issue in the candidate loop (`table.insert(skips, { id = i.id, reason = i.stale })`, its proto-engine.patch), and makes `new raft` and `fold` refuse a stale prepared issue. c0286's verdict picks its candidates with a test of its own, so a stale tied member counts as a candidate and goes into the tie's op. `raft-plan --apply` then runs `./zn new raft chore … <stale id> …`, the command refuses it, and the ops before it in the plan have already run.
- The document says the in-flight items "none reads or writes `tied:` or the tie verdict … an independent skip". They are not independent. The same is true of `unknown type`, which the loop skips and the verdict does not check.
- c0161's `design-record` hashes the document without `status:`, `raft:` and `design:`, so it includes `tied:`. Writing the line on a prepared member whose newest round quotes a `Design record:` makes that member stale. c0161 says "A chore that edits another prepared issue's design files runs the same round for the edited issue". On today's main step 5 writes two prepared members, c0248 and c0250.
- c0286's new z-raft §1 bullet also sits directly above the "an issue with no `size:`" bullet, which c0161 rewrites. These are adjacent hunks, so whichever lands second conflicts.
Recommendation:
- Use one predicate, for example `plannable(i)`, in both the candidate loop and the verdict. Then every reason the loop skips a candidate (no `size:`, a `tied:` problem, unknown type, and c0161's `stale` when it lands) makes that member a waiting one in the verdict (`<id> (stale)` and the like). State this in Behaviour 3 and Maintainability.
- Say that whichever of c0161 and c0286 lands second adds the stale case to ties.spec and resolves the z-raft §1 bullets.
- For the migration, write lines only on members whose design is not ready. Ties are undirected, so one line connects the whole tie, and no prepared design, `grouped:` record or c0161 record changes.
- When a family has no such member, step 5 writes one prepared member's line and, if c0161 has landed, runs c0161's design round for it.
- F2's spec checks that each family is connected, not that every raftless member carries the full list.
Lesson: z-raft/interface-names-every-writer; z-design/new-front-matter-lines-meet-every-hash

### F4 [medium] The documented way through a dispatched stop invites a duplicate raft, and cause 6 sends a raft that is only mid-rafting to z-raft with arguments
Where: Restated rules ("`./zn dispatch retry <id>` once the rest are prepared rafts the whole tie"); Behaviour 3, cause 6; ties.spec's expectation "is backlog, preparing: z-raft with arguments decides".
Evidence:
- `dispatch.next` gives a prepared, raftless issue the `raft-plan` step (`raft-plan --apply` in `.worktree/raft-<id>`), and `dispatcher.facts` reads `localRaft` from that worktree only.
- With the c0248 family's five `new` issues each dispatched, every earlier member stops with "raft-plan put <id> in no raft (see its skip line)". The last member's own chain then rafts the whole tie and carries it through z-raft and the raft gate.
- Retry an earlier member as the document says while that rafting PR is open, and on origin/main every member is still raftless and prepared. Its `raft-plan` step plans `new raft` over the same tie again. That publishes a second raft and opens a second rafting PR whose `raft:` lines conflict with the first. The gate refuses it once the first merges, and the claimed raft is left for someone to `release`.
- Cause 6 treats `preparing` like active or done. A raft claimed by a fold or recombine still in progress (R0093 was `preparing-lynx-crimson-pink` this morning) needs only that rafting to land and `raft-plan` to run again, not z-raft with arguments. c0250's planned `blocked` raft status is a third case: its way through is `./zn resolve <R-id>`.
Recommendation:
- Give the way through per case, in Restated rules and in the cause-7 skip text. The last member's prep, dispatched or not, is followed by one `raft-plan` that rafts the whole tie. A stopped member's chain is retried only after that rafting PR has merged; it then follows the raft. If the last member was prepared outside the dispatcher, retry one stopped member, not each.
- Split cause 6: `preparing` (wait until that rafting lands, then run raft-plan again) versus active, done or single (z-raft with arguments decides). Change ties.spec's "backlog, preparing" expectation to match.
Lesson: z-design/dispatched-refusals-name-their-way-through

### F5 [medium] The order of the causes is stated but no case pins it; a reordering mutant survives and prints a wrong instruction
Where: Behaviour 3 (causes 1 to 7); the Rules and mutants table.
Evidence: every case in "skips a tie one raft can't hold" and "never rafts a tie apart…" has exactly one cause, and no case combines two. The mutant "check waiting members (7) before the raft's state (6)" passes all 13 cases. Its effect on the c0248 family, if the raft that holds some of it is readied while c0249 is still new: the skip says "c0249 (new, design draft) not prepared yet: raft-plan rafts them together when every one is". That never comes true, because once c0249 is prepared cause 6 applies. The design itself relies on this order ("or is skipped naming R0093's state").
Recommendation: add a row "the first cause in the stated order is the one named", with cases that combine causes 6 and 7 (a member in an active raft plus a `new` member gives cause 6's text), 1 and 7, and 2 and 3. Run the mutants "waiting before the raft's state" and "solo before type".

### F6 [low] E4's record is not what the committed script produces, and its command is not bounded
Where: Unknowns & experiments, E4; `experiments/mutants.py`.
Evidence: I counted each mutant's anchor in proto-c0286's `raftplan.luau`. M7's anchor (`else { kind = "new", raft = nil, type = first.type, … single = false }`) occurs 0 times, because stylua split it over several lines. So the script prints "M7: anchor not found once" and exits 1, where E4 records "all 21 … fail on an assertion". The case does kill M7 by reading: `lines()` appends " single". E4 gives the command as a bare `python3 -I mutants.py`, not through `./zn run --time`. Its `ENV` also leaves `ZN_REAL_GIT`, `ZN_REAL_GH` and `z-nile/bin` on `PATH`, all of which check.sh's `undispatched` strips.
Recommendation: change M7's anchor to the formatted text. Rerun as `./zn run --time <s> -- env -u … PATH=<stripped> python3 -I mutants.py <home>` with the same variables `undispatched` removes, and record the output.

### F7 [low] "Between two lines nothing else rewrites" is false: `./zn land` rewrites `title:`
Where: Behaviour 1 (where the line sits); step 5; plan-cli's fixture.
Evidence: zz-rules says `./zn land` pushes a capture's edits, including "their sections, `title` and `depends_on`". A capture that retitles c0249 while c0286's branch inserts `tied:` right after `title:` makes adjacent hunks, and git merges adjacent hunks as a conflict (zz-rules: "A conflict on `raft:` or `depends_on:` (they are adjacent lines)"). Of the front-matter lines, only `id:` and `type:` are never rewritten.
Recommendation: either put the line between `id:` and `type:`, or keep it after `title:` and state that rare conflict and how to resolve it. Keep step 5, the plan-cli fixture, the z-design text and F2's placement check consistent with the choice.

Verdict: changes
