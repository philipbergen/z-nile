# Review 006: R0042 (design mode)
Inputs: prep-z-nile at a232afe (R0042.md, check.sh, harvest.md; c0111 and c0119 documents, check.sh files and acceptance specs; the 19 lesson files). The prototype `.worktree/proto-scope-fidelity` (5c4779e plus uncommitted c0111 and c0119 text; its c0111/c0119 specs, c0119 check.sh and lessons are byte-identical to this tree). origin/main at fetch time.
Rounds 001 to 005 reviewed the released c0114 to c0118 design, so none of their findings is repeated here. c0111's settled R0040 decisions are not re-litigated. F6 and F8 rest on new evidence: item 11 and the move into R0042.

Run on the prototype: c0119 `check.sh` 3/3, c0111 `check.sh` 9/9, `lessons --check` (`19 lessons, 75 harvest entries, ok`), `--uncovered R0040 R0042` (covered), RC1's grep (13 lines). `luau-lsp analyze` of the member specs: see F1.

Lessons pass (item 10): each design lesson's `check` was asked of this draft. Failed: `ticket-prep/rerun-skipped-checks-after-edits` (F1), `ticket-prep/new-rules-migrate-existing-work` (F2), `ticket-prep/required-steps-on-every-path` (F3), `ticket-prep/spec-design-correspondence` (F4), `ticket-prep/restated-rules-move-together` (F5) and `ticket-prep/instructions-runnable-where-they-run` (F9). The others pass or don't apply (no locks, guards, parsers or new list entries; item 11 follows item 10 and nothing enumerates the items).

The six new lessons: each is a rule another raft could break, with a general `check`, so none is a restated finding. The two scope lessons carry the defects of F2 and F5 in their `check` text ("as on origin/main before this prep", "a Checked criterion"), so they change with those fixes. Harvest mapping: see F11.

Scope fidelity (item 11): c0119's title and Problem are unchanged from origin/main. Every Problem outcome (the frozen Problem, recorded decisions, no prescribed cuts, escalation, the author asking instead of accepting, the lesson) has Design text and AC1 or AC2. The user's second request in R0042's Theme ("we want a memory/lesson mechanism as part of the flow") is c0111 as a member. c0111's Problem has been rewritten: see F6.

### F1 [high] c0119's `scope-lessons.spec` fails the type check, so `promote-check R0042` (RC0) and `done`'s full gate fail, and the file is sequestered
Where: tracker/issues/c0119/acceptance/scope-lessons.spec.luau lines 20 and 28; c0119 Unknowns & experiments E1; R0042 Experiments phase
Evidence: in the prototype (where `scripts/tracker/lessons.luau` exists), `luau-lsp analyze --base-luaurc=.luaurc --platform=standard tracker/issues/c0119/acceptance` exits 1:
- `scope-lessons.spec.luau(20,16): TypeError: Cannot call a value of type {string} in union: {string} | {|  |}` (`for _, s in sources[id] or {} do`);
- `scope-lessons.spec.luau(28,13): TypeError: Argument count mismatch. Function 't.expect' expects 0 to 1 argument, but 2 are specified` (`t.expect(string.find(p, "scope", 1, true))`; `find` returns two values).

c0111's specs analyse clean (exit 0). The gate type-checks `tests scripts` (scripts/check.sh:66) but not `tracker/`, so the prep PR is green today. `promote-check` and `done` copy the spec into `tests/acceptance/c0119` and run that same analyze, so RC0 "acceptance specs will survive promotion" fails, and so does `done`'s full gate. The executor may not edit the file and has to stop. E1 records specs, mutants and check.sh results, but no `promote-check R0042`. It could not have: the prototype's R0042.md still lists `[c0111, c0114, …, c0118]`, so a promote-check there skips c0119.
Lesson: ticket-prep/rerun-skipped-checks-after-edits
Critique: the obvious fix is to patch the two lines. That fixes this file. But the step that would have caught it never ran on this raft, because the prototype's membership is out of date.
Consequences: the patched lines change no assertion, so the mutants still apply. A prototype whose R0042.md matches the real one also makes promote-check cover both members.
Recommendation: bind the list: `local list: { string } = sources[id] or {}`, then `for _, s in list do`. Wrap the find: `t.expect((string.find(p, "scope", 1, true))).toBe(nil)`. Then sync the prototype's R0042.md (and c0119's `raft:`) with this tree, and run `scripts/tracker.sh promote-check R0042` there. Record its `promote-check OK` in c0119 E1 and in R0042's Experiments phase, and add a source for `ticket-prep/rerun-skipped-checks-after-edits`.

### F2 [medium] Item 11's baseline (origin/main when prep starts) is not the user's "frozen after capture": a rewrite that already landed becomes the scope, and five prepared rafts are not addressed
Where: c0119 Design ("The rule in one place … A later prep of the same issue starts from whatever landed"); ticket-prep Appendix paragraph; lesson `never-narrow-captured-scope` check; R0042 Risks ("A prep mid-round (R0041's, R0039's)")
Evidence:
- c0119's Problem quotes the user's choice: "**The Problem is frozen after capture.**" The Design instead takes the Problem as it is on origin/main when prep starts. That baseline includes every Problem edit an earlier prep PR landed.
- I compared each prepared raft member's Problem in the commit that added its document with origin/main. All ten changed: R0012's f0027, f0028 and f0029; R0030's c0083; R0035's f0100, f0101, f0102 and f0104; R0039's c0075; R0041's c0106. Some changes are the user's (f0101: "Revised 2026-10-17 …"). Others read like a prep author's narrowing: c0106 now says "this chore is what is left … So this chore only narrows them".
- If any of these rafts is stopped and prepped again, item 11 diffs against the rewritten text and finds nothing.
- R0042's Risks says R0039 and R0041 are mid-round. Both are `design: ready` and `prepared` on origin/main.
Lesson: ticket-prep/new-rules-migrate-existing-work
Critique: the tempting fix is to correct the Risks line and leave the baseline alone. Then any rewrite that gets past one review stays the scope forever. That is how R0042's own cuts would have stuck if its prep PR had merged.
Consequences: a capture-based baseline must find "the capture" in git. The decisions already on c0114 to c0118 use the form "Decided with the user (2026-10-20):", not `Scope decision (user, …)`, so either form has to count. Prepared rafts with a changed Problem need a decision before they are readied, and that adds work to `ready`.
Recommendation: escalate to the user: (a) the baseline is the Problem as captured: the last commit whose subject starts `tracker: new` that touched the document (`git log --format=%h --grep '^tracker: new' origin/main -- <doc>`, first line), plus decision lines. Accept "Decided with the user (date)" bullets too, and do a one-time listing of the ten changed Problems above, for the user to confirm before each raft is readied. Cost: one more git command per review, and one user pass over ten issues. (b) Keep origin/main as the baseline and write in Problem/Risks that landed preps are accepted as scope. Cost: past cuts are kept. Either way, fix the R0039/R0041 sentence, and update the lesson's check and the spec's `on \`origin/main\` when prep starts` assertion to the chosen wording.

### F3 [medium] Nothing checks scope after the final round's answers, where R0042's cuts were made
Where: ticket-prep step 5.3 (new bullet) and 5.5; review item 11; lesson `never-narrow-captured-scope` "How to apply" ("before each round and before `design: ready`, diff each item's Problem")
Evidence:
- c0119's Problem says each cut was "accepted … in a refute" and then written back into the Problem.
- Item 11 runs only in a review round. The final round's answers are never reviewed: ticket-prep step 4 runs no further round after the final one, and R0040's design-refute-005 says "No reviewer re-checks these answers".
- So an author who answers the final round by cutting scope, or edits the Problem after the last review, meets no check before `design: ready`. Step 5.5 ("Confirm the harvest") checks only `--uncovered` and `--check`.
- The lesson says to diff "before `design: ready`", but no skill text tells the author to.
Lesson: ticket-prep/required-steps-on-every-path
Critique: "the 5.3 bullet forbids it" is a rule with nothing that notices when it is broken. The user turned down a `tracker.sh scope` command, so the fix must not be a new command.
Consequences: a second place states the diff rule, so it has to point back to **Scope is what was captured** (restated-rules-move-together). That adds one spec assertion and one row.
Recommendation: in ticket-prep 5.5, before "set `design: ready`", add: "Then diff each member's document against the baseline (**Scope is what was captured**): its title and Problem may only have gained detail and `Scope decision` lines; anything else goes to the user before `design: ready`." In scope-docs.spec, assert that the clause sits in step 5, item 5, before ``set `design: ready` ``. Add a row with the mutant "drop the clause", run on the prototype.

### F4 [medium] Item 11's two main checks have no spec case, so a mutant that drops either one survives
Where: c0119 Rules and mutants; scope-docs.spec case "review never prescribes a cut, and design mode checks scope fidelity after Lessons"
Evidence: on item 11 the case asserts only `` `git diff origin/main -- <doc>` ``, `` `Scope decision (user, YYYY-MM-DD)` ``, `moved into Non-goals` and `is **high**`. Deleting "Then check that every outcome the Problem asks for has a Design and a Checked criterion." passes every case. That sentence catches an outcome that the Design silently leaves out while the Problem stays untouched, which is the other half of the user's rule. Deleting ", or a Problem rewritten to match a smaller design" also passes. Neither rule has a row. The same goes for "Without that line, the answer is a redesign that keeps the outcome" (5.3) and "including what keeping the full scope would cost" (review paragraph).
Lesson: ticket-prep/spec-design-correspondence
Critique: these are behavioural rules in the Design, so each needs a row whose mutant fails.
Consequences: the new assertions pin wording that F5 changes, so write them after F5's text is settled.
Recommendation: add the four phrases as assertions in the matching cases, plus four rows (mutant: drop the clause), each run on the prototype and recorded in E1.

### F5 [medium] "Every outcome needs a Checked criterion" contradicts the Judged and Observed criteria that ticket-prep and testing allow
Where: review item 11 (Appendix); lesson `never-narrow-captured-scope` check; c0119 Design bullet for item 11
Evidence: ticket-prep step 4 and the testing skill allow **Judged** (with a rubric) and **Observed** (Studio steps) criteria when no measurable proxy exists. Game outcomes such as feel or readability on a phone often have only those. Item 11 says every outcome must have "a Design and a Checked criterion". A reviewer then either rates an outcome that has only an Observed criterion as a finding, and the item doesn't say how severe, or pushes the author toward a fake proxy that a hard-coded implementation passes (review item 2).
Lesson: ticket-prep/restated-rules-move-together
Critique: dropping "Checked" altogether would let an outcome through with no criterion at all.
Consequences: none beyond the wording, the lesson's check and F4's assertion.
Recommendation: word it as "a Design and an acceptance criterion: Checked, or Judged or Observed only where the testing skill allows it, and an outcome with no criterion is **high**". Use the same words in the lesson's `check`, and pin them in scope-docs.spec.

### F6 [medium] c0111's Problem was rewritten against origin/main, and a captured outcome (metrics) became a Non-goal, with no recorded user decision
Where: `git diff origin/main -- tracker/issues/c0111/c0111.md`, Problem, Non-goals and Solution
Evidence:
- The Problem's harvest bullet lost "turns the recurring findings into lessons … Lessons land with the prep PR." The apply bullet lost "The reviewer checks them too, and `ready-raft` puts the matching ones in the execution prompt."
- Both are replaced by new wording, and two new bullets are added. The header now dates all four to the user ("(2026-10-20)"). At least one of them is the author's refinement: R0040 design-review-003 asked to mark that bullet "(refined under Design, The skills)".
- Under item 11 the Problem "may only gain detail and `Scope decision` lines", so this diff fails. No outcome is lost: the prep-PR landing is in Design line 174, and "matching" became all build lessons.
- Separately, the captured Solution had "**metrics:** report findings per tag across rafts, to show whether lessons reduce review rounds". That is now the Non-goal "Metrics over lessons (findings per tag, rounds before and after)". It was the only captured way to tell whether the mechanism works. R0040's reviews and refutes record no user decision on it.
- c0119's rule protects only the Problem, so after this raft lands nothing would catch a cut like this.
Critique: once this raft lands, its own first member is an example of what item 11 forbids. If the R0042 prep PR merges like this, the rewritten text becomes the baseline (see F2).
Consequences: restoring the captured bullets keeps the Problem readable, as long as the refinements move to Design. The metrics question also asks whether a captured Solution idea is scope at all. c0119's user choice says only the Problem is.
Recommendation: escalate to the user:
- (a) Restore the two captured bullets verbatim. Add the user's 2026-10-20 additions as `Scope decision (user, 2026-10-20): "<their words>"` lines, only for what the user actually said (separate folders per skill, harvesting code reviews, backfill in c0112). Move the role-routing refinement to Design.
- (b) For metrics, either the user confirms the Non-goal (a decision line), or c0111 delivers "findings per tag, and rounds before and after lessons" in `tracker.sh metrics`, with a Checked criterion. Cost: one more metrics section and spec.
- Also ask whether captured Solution ideas count as scope, and record the answer in c0119's Problem.

### F7 [low] "Split into sequenced rafts, never shrunk" doesn't say how to split one issue, and the split that item 11 sees looks like a drop
Where: ticket-prep paragraph **Scope is what was captured.**; review item 11
Evidence: an issue belongs to one raft. An issue too big for one raft (c0114, which moves the whole tracker, is next in the chain) can only be split by moving outcomes into new issues. Item 11 then sees outcomes removed from the original Problem, which is **high** without a decision line. But the paragraph's last sentence reads as if the author may split without asking. R0042's own split of c0120 out of c0114 was the user's decision (ab750c0).
Recommendation: add to the paragraph: "Splitting an issue moves outcomes into new issues captured through make-issue, and it is the user's call: the original Problem gains a `Scope decision` line that names the new ids." Add an assertion and a row.

### F8 [low] c0111 still names R0040 where execution now happens in R0042, and R0040 is left as an empty prepared raft forever
Where: c0111 JC1 ("every lesson R0040's harvest creates (… the code-review ones from execution)"); Implementation step 6 ("Harvest each code review round … Then AC8 passes"); R0040.md (`issues: []`, prepared); c0112 Solution ("Prep this raft after R0040 lands")
Evidence:
- Code reviews now go in `tracker/rafts/active/R0042/review-NNN.md` and are harvested into R0042's `harvest.md`. So JC1 literally rules on no code-review lesson, and step 6 has no effect on AC8 (`--uncovered R0040`). RC2 covers R0042's reviews, but JC1 does not.
- R0040 will sit in the backlog as `design: ready` and prepared with no members. `ready` refuses it ("has no member issues"), while the board's rule ("Ready when design is ready and … prepared") lists it as Ready.
- c0112's "after R0040 lands" can never happen.
Recommendation: make JC1 read "every lesson R0040's and R0042's harvests create", and step 6 read "Then RC2 passes". Write in R0042's Risks what becomes of R0040: done with the raft (by hand at `done`), or kept with a note in its Theme that it is never readied. Then point c0112's sentence at R0042 (that is a capture edit, so do it through the user or `land`).

### F9 [low] The scope paragraph tells the author to use AskUserQuestion, which only Claude Code has
Where: ticket-prep paragraph ("ask them (AskUserQuestion, …)")
Evidence: the prompt and the skills are written for "any agent (Opus, Grok, ...)" (ready-raft), and the next rafts of this programme (c0117) dispatch steps headless across CLIs, where nobody can be asked.
Lesson: ticket-prep/instructions-runnable-where-they-run
Recommendation: "ask the user (AskUserQuestion in Claude Code; otherwise stop and report the options and their costs as your result)". Keep the spec's `AskUserQuestion` assertion and add one for the fallback.

### F10 [low] This is round 6, but ticket-prep allows at most 5 and gives re-preps no rule
Where: ticket-prep step 5.4 ("up to 5 rounds … round 5, which is always final"); R0042 Risks
Evidence: rounds 001 to 005 reviewed a design the user rejected. This round's file is `design-review-006.md`, which the round rule does not define. So the author can't tell whether this round is final, or whether a high here (F1) goes to the user or to another round. `metrics` will count 6 or more design rounds for R0042.
Recommendation: escalate to the user: how this re-prep counts its rounds (for example, round 006 is its round 1 and up to four more follow). Record the answer in R0042's Risks, so a later re-prep can follow it.

### F11 [low] Three harvest entries are marked one-off although their defect class recurs
Where: tracker/rafts/R0042/harvest.md
Evidence:
- design-review-003 F4 ("every issue lists its own acceptance spec … the root spec always joins `strongest`") is the same defect as 002 F2, which maps to `ticket-prep/spec-design-correspondence`, but it is marked one-off.
- 001 F14 (data sources unspecified) and 002 F11 (`.models.toml` content unspecified) are both "the design names a file or data source and doesn't specify its content", so the class recurs, and both are one-offs.
- 003 F6 ("the prep tree edited a live skill file to point at a file no branch had") is a rule another prep could break: prep edits become live text when the prep PR merges.
Recommendation: make 003 F4 a source of `spec-design-correspondence`. Either add a lesson (for example `ticket-prep/specify-every-named-artifact`, with a check asking whether every file, table or data source the design names has its content and its fallback written down) that sources 001 F14 and 002 F11, or say in their one-off reason why it doesn't apply. Map 003 F6 to `ticket-prep/instructions-runnable-where-they-run` or a new lesson.

Verdict: changes
