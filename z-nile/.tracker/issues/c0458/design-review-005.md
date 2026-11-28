# Review 005: c0458 (design mode)
Inputs: prep worktree `prep-collapse-reviews-and-tighten-caps` at 1191c74e1 with its uncommitted `z-nile/.tracker/issues/c0458/{c0458.md,check.sh,guesses.md,harvest.md,acceptance/{caps-modes,walk,docs,publish}.spec.luau,experiments/prototype.patch,design-refute-004.md}`; `design-review-004.md`. Checks made: `experiments/prototype.patch` (469 lines) applied to a `git archive 1b78199b0` copy in `.cache/c0458-r5-proto`, its own repository, with the four specs copied into its `z-nile/tests/acceptance/c0458r5`. On that copy publish passes 2/2, walk 5/5 and caps-modes 4/4. With the base `publish.luau` put back, `publish.spec` fails on an assertion (`publish.spec:28: expected true, got false`). Eight mutants of the prototype's `publish.luau` were run one at a time on that copy, each restored after its run (F1). One probe spec ran on the copy (F2), and one read-only probe of `trace.deriveClaims` on the document (F6). Also read: `z-nile/engine/publish.luau:30-33`, `:420-478`, `:483-615` and `:720-810`, `main.luau:7205-7300`, `lightgit.luau:174-198`, `easy.luau:152-179`, `workread.luau:392-437`, `work.luau:405-430`, `trace.luau:427-455`, `tests/tooling/light-publish.spec.luau:389-474`, `tests/tooling/light-path.spec.luau:1296-1400`. Every run went through `./zn run`. One slip of my own: my first copy stored a fixture identity in the copy's own `.git/config`, and the runner inside the copy refused to start. I rebuilt the copy without it. The real repository's configuration was not written (its identity still comes from the user's global file).

Round 4 answers. The refute file disputes nothing, so there is no refutation to accept or re-raise.
- F1 is fixed for the move itself. Item 10 takes Route A, the prototype's `raiseEdit` accepts the stop of a raft of three that is not light, and the spec is red on today's publisher and green on the prototype. The two mutants the answer names fail at `publish.spec:42` and `:53`. Touched modules, the Guards line, G3 and `risk: risky` are in place. No promoted spec names `raiseEdit` or builds a `Raise`, so the Overrides line needs no new entry. What is not real is the claim that AC4 pins every refusal round 4 listed (F1 below), and the widened guard has a hole of its own (F2 below).
- F2 is fixed in the new sentence, and the walk does check `roundsProblem` (`work.luau:408`) before `levelProblem` (`:411`). The sentence it corrects was left in place (F4 below).
- F3 is not fixed in any file the executor reads (F4 below).

### F1 [high] AC4's spec still passes with six of the guard's rules removed, one of them a rule AC4 names
Where: `acceptance/publish.spec.luau:38-59`; Acceptance criteria AC4 ("refuses ... a lowered or wrong raised level"); Design item 10 ("for each raised ticket, `status`, `risk` (to its raised level, never lower), `design` (to `draft`) and `raft` (this raft to empty) ... `validateMoves` requires the raft and every listed ticket in the same publish"); Rules and mutants row "the publisher accepts only the exact documents and keys of a multi-ticket raise"; refute-004 F1 ("pins ... every refusal the reviewer listed")
Evidence: each of these changes to the prototype's `publish.luau`, made alone, leaves `publish.spec` at "2 passed, 0 failed":
- `and now >= was` removed, so a raised ticket's `risk:` may go down. The spec's "risk not lowered" line (`:47`) raises to risky and writes normal, so it is refused by `after.keys.risk == level`, the same test that line `:48` exercises. No case writes the raised level onto a ticket that was above it.
- `and after.keys.design == "draft"` removed.
- `before.keys.raft == raise.raft` removed for a raised ticket, so a ticket of another raft is accepted.
- `after.keys.raft == ""` removed for a raised ticket, so the ticket may keep a raft.
- `and level ~= "easy"` removed.
- `if any and not all then` replaced by `if false then` in `validateMoves`, so the raft and its members need not move together.

The last rule does more than its message says. A released member that is moved with only its `status:` changed passes `movedEdit`, so it is never judged as a raise. Only the together rule then refuses the publish. Without it origin/main can hold a raft with `issues: []` whose members still say `raft: R0306`. Nothing tests this rule today either: no spec holds its message, and `validateMoves` is local to `publish.luau`, reached only through `publish.commit`. Round 4 listed "a raise naming a ticket that is not in the move" and "a partial move" among the refusals to pin. Neither has a case, a Rules row or a word in AC4.

`publish.spec:58` (`t.expect(ok ~= "").toBe(true)`) cannot fail: `ok` is built and never given to `raiseEdit`.
Critique: the guard is the reason this ticket became `risky`, and the Guards line rests on "AC4 pins each refusal". Today's cases for five of these rules sit in `tests/tooling/light-publish.spec.luau:420-472`, written for the one-ticket `Raise`. The executor must rewrite that case for the new shape, and a tooling spec is the executor's to edit, so the sequestered spec is what holds the rules. The tempting fix is to add the one "lowered" case AC4 names and leave the rest to the tooling spec.
Consequences:
- The together rule needs a seam a pure spec can reach, or an IO case with a fixture origin. A seam is a new export, and the prototype must hold it so `promote-check` sees it.
- "Never lower" has a second half: a ticket already at the raised level is accepted. F3 decides whether that half can still happen, and the two cases belong together.
Recommendation:
- In the refusal case of `publish.spec`, add one line per rule, each differing from the accepted raised document in one thing:
  - a raise to normal written onto a ticket that was risky;
  - `design: ready` kept;
  - a raised ticket that came from `raft: R7777`;
  - a raised ticket that keeps `raft: R0306`, and one that gets `raft: R9999`;
  - a raise to `easy`.
- Replace line `:58` with the control `raiseEdit("c0011", ticket("c0011"), ok, raise)` is true.
- Move the together rule into an exported pure function that `validateMoves` calls, for example `publish.raiseWhole(raise, judged: { [string]: boolean }): string?`. Pin it in `publish.spec`:
  - every listed document judged a raise gives nil;
  - nothing judged a raise gives nil;
  - the raft judged and one released member not gives a refusal;
  - a raised ticket judged and the raft not gives a refusal;
  - a released member judged alone gives a refusal.
- Add the function to the prototype and run two mutants: the rule dropped, and the released members left out of it.
- Give each rule its own Rules row with its mutant, marked `run` with the red line recorded in E5.
- Name the together rule and the raised ticket's `design:` and `raft:` rules in AC4's text.
Lesson: z-design/spec-design-correspondence
Erred: z-design
Upstream: none

### F2 [medium] The guard accepts a raise that raises no ticket, and nothing says `stop` takes the raise path only when a ticket is raised
Where: Design item 10 ("`RaftFact.raised` becomes `{ [string]: string }?`"; "`./zn stop <R-id>` (`main.luau:7265`) ... (the code now at `#ids == 1` generalises)"; "for the raft, `status` and `issues` (from exactly the raised and released ids to `[]`)"); `publish.raiseEdit` in `experiments/prototype.patch` (`return #want > 0 and ...`); `easy.raisedBy` in the patch (`return out, nil`); `main.luau:7265`
Evidence: on the prototype, with `raise = { raft = "R0306", raised = {}, released = { "c0010", "c0011", "c0012" } }`, `raiseEdit` answers true for the raft going from `[c0010, c0011, c0012]` to `[]`, and true for c0010 losing its `raft:`. `#want > 0` counts the released members, so a raise needs no raised ticket. `easy.raisedBy` answers an empty table, never nil, for a review with no `Level:` line and for no review at all. The prototype's walk already allows for that: it tests `r.raised ~= nil and next(r.raised) ~= nil`. `stop` today tests `raised ~= nil and #ids == 1` (`main.luau:7265`), and item 10 tells the executor that this code "generalises". Generalised as written, with `#ids == 1` dropped, every `./zn stop <R>` of an active raft that has a layer takes the raise path: each member loses its `raft:`, the raft gets `issues: []`, and the publisher accepts all of it. A plain stop then dissolves the raft, where z-stop promises to undo `ready`. A final review whose only `Level:` line is at the ticket's own level gives the same empty table.
Critique: the Guards line says the exception "accepts only the exact set of documents and keys `stop` writes". `stop` never means to write a raise with no raised ticket, and the guard is the place that must refuse when `stop` is wrong. The tempting fix is the `next(...)` test in `stop` alone, which leaves the guard open.
Consequences:
- Once the guard refuses an empty raise, a `stop` that takes the raise path by mistake fails instead of dissolving the raft. The design must then say which path a raft with nothing raised takes, and a case must pin it.
- `raisedBy` has three callers (`workread`, `lightgit.raisedOf`, `lightgit.of`). They need one convention for "nothing raised", nil or an empty table, or each will test it differently.
Recommendation:
- In item 10, state that `stop` takes the raise path only when at least one ticket is raised. Otherwise it is today's plain stop: the raft keeps its `issues:` and every member keeps its `raft:`.
- State what `RaftFact.raised` and `lightgit.raisedOf` hold when nothing is raised. Nil is the smaller change: the two readers turn the empty table into nil, and `raised ~= nil` keeps its meaning at every caller.
- Make `raiseEdit` answer false for every document when `raise.raised` names no ticket. Add two lines to `publish.spec`'s refusal case (the raft and a member under `raised = {}`), change the prototype, and add a Rules row with the mutant "an empty raise accepted", run.
- Add an IO case for the executor in `tests/tooling/light-path.spec.luau`: a fixture raft of three tickets with a `final-review-001.md` on its tip that holds no `Level:` line, and one whose only line is `Level: c0011 normal` for a c0011 that is normal with a full design. After `./zn stop` the raft still lists its three issues, each member still names it, and `./zn ready <R>` readies it again.
Erred: z-design
Upstream: zz-review

### F3 [medium] A ticket whose `risk:` was already raised on main is no longer stopped as a raise, against a case the tooling pins today
Where: Design item 10 ("`levels` maps each ticket of the raft to its current `risk:`"; "A line at or below a ticket's own level raises nothing"; "`easy.raised` ... stays for the light path's callers"; "The existing single-ticket path (`#ids == 1`) is this rule with one member"; "`risk` (to its raised level, never lower)"); `acceptance/walk.spec.luau` AC8 (`raisedBy({ "Level: normal\n" }, { c0010 = "normal" })` is `{}`); `tests/tooling/light-path.spec.luau:1371-1400`; Test plan ("`light-path.spec` (the code-review cases removed, the final-review ones kept)")
Evidence: the existing case "c0435 review 3 B/C: a risk already raised on main still stops, and the emptied raft is not offered" does this:
- it builds a light raft of easy c0010 and writes a final review with `Level: normal`;
- it raises c0010's `risk:` to normal by a tracker change on main;
- it runs `./zn stop` and expects `risk: normal`, `design: draft` and the raft not offered again.

`stop` reads the tickets from the main checkout after its pull, so the "current `risk:`" it would give `raisedBy` is normal. By item 10 and AC8 the line then raises nothing. `stop` gives the raft back whole, and c0010 keeps `design: ready` on its short note. The walk changes the same way. Today `easy.raised` answers `normal` and the walk says `release`. With `raisedBy` nothing is raised and the raft goes on to its next final-review round. The publisher still keeps `now >= was` for exactly this case (the comment the prototype deletes says "a risk the author already raised on main equals it"), but under item 10 no caller can produce that raise any more.

The design names this case nowhere, and item 10 can be read two ways. If `easy.raised` "stays for the light path's callers", `stop` of a light raft keeps today's answer, and the walk, which item 10 moves to `raisedBy` "for every raft", disagrees with it. If the single-ticket path "is this rule with one member", the case goes red and the executor inverts it.
Critique: this came from round 3's own Recommendation ("keep a raise only when its rank is above the ticket's level"). It solved a normal ticket confirmed at normal and did not look at a ticket whose level moved after the review was written. The two differ in one fact: the first has a full design, and the second still has an easy ticket's short note. The tempting fix is to keep `easy.raised` for a raft marked light. That keeps the existing case green, but an easy member of a raft of several, which this ticket now lets `ready` accept, has the same gap.
Consequences:
- Keyed on the short note, `raisedBy` needs a second fact per ticket. Both places that build its input (`workread` for the walk, `lightgit` for `stop` and `done`) must build it the same way.
- The brief's sentence "A line at or below the ticket's own level raises nothing" changes with the rule.
- The publisher's "already at the raised level is accepted" half becomes reachable again and needs its case (F1).
Recommendation: decide the rule in item 10 and pin it. The rule that covers both tickets: a line at the ticket's own level raises it when the ticket still has only a short note (`easy.note` reads one), and raises nothing when the ticket has a full design. A line below the ticket's level never raises.
- Give `raisedBy` that fact as a third argument (ticket to "has only a short note"), built with the levels map in one function that `workread` and `lightgit` both call.
- Add AC8 cases: a bare `Level: normal` for c0010 at normal with a short note gives `{ c0010 = "normal" }`, the same line without the note gives `{}`, and `Level: c0010 normal` in a raft of three with the note gives the raise.
- Name `light-path.spec.luau:1371` in the Test plan as kept green unchanged, with one added assertion that `./zn work next <R>` answers `release` there.
- Add an IO case for a raft of three: easy c0010 on a short note, a review with `Level: c0010 normal`, and c0010's `risk:` raised on main. `work next` answers `release` naming c0010, and `stop` publishes `design: draft` for it.
- Add `publish.spec` lines: normal to normal under a raise to normal is accepted, beside F1's refused risky to normal.
- Add a Rules row with the mutant "an own-level line ignored for a ticket on a short note", run on the prototype, and reword the brief's sentence.
Erred: zz-review
Upstream: none

### F4 [low] Two of round 4's answers are in the refute file but not in what the executor reads
Where: refute-004 F3 ("the walk's release wording becomes \"raised c0011 to risky, c0012 to normal\""); `work.forRaft`'s `release` text in `experiments/prototype.patch`; Design item 10, the parenthesis after `easy.raisedBy`'s signature
Evidence:
- Round 4 F3. The patch still says "A review of {r.id} says {named} not easy", with each ticket written as `c0011 (Level: risky)`. The words "raised c0011 to" are in no file but the refute. Item 10 says the text is "pinned by `walk.spec` AC9", which pins only the ids and the level words. The executor copies the prototype's text.
- Round 4 F2. Item 10 now says `workread` builds a new map, but the same item still says "(`levels` maps each ticket of the raft to its current `risk:`, which `workread.luau:404` already holds)". Line `:404` is `rounds.highest(levels)` over a list.
Critique: an answer that lives only in the refute file binds nobody. The next reader sees the old text and the old citation.
Consequences: none. AC9 does not pin the words that change.
Recommendation: change the patch's `release` text to the new wording and rerun `walk.spec` on the prototype. Delete the "already holds" parenthesis, or point it at the sentence that describes the new map.
Erred: z-design
Upstream: none

### F5 [low] The records do not hold the publisher runs
Where: Unknowns & experiments E5 ("`experiments/prototype.patch` (366 lines ...)", its file list and its mutant list); Test plan line "Run result at prep"; Affected specs ("New: ..."); Rules row "run: AC4 red for both"
Evidence: the patch is 469 lines and holds a `publish.luau` hunk. E5 says 366 lines, lists no `publish.luau`, and does not record the two publisher mutants the row marks `run`. The Test plan's run line names caps-modes, walk and docs only. `publish.spec` is red on origin/main in one of its two cases (`expected true, got false`); the refusal case passes there, because the old guard refuses everything. The "New:" list names three specs, not four. "AC4" now means two things: E5's "`final-review` back to `all = \"ultra\"` (AC4)" is caps-modes's case, and the row's "AC4 red" is the publisher criterion. Design mode item 0 asks for each `run` outcome in Unknowns & experiments. Round 3 F4 was this same defect one round earlier.
Critique: the next reader cannot tell which run backs the `run` mark, or which AC4 it is.
Consequences: none.
Recommendation: update E5 to the patch's length and files, list every publisher mutant with the line that turned red, and say which spec each "AC4" belongs to. Add `publish.spec` to the run line and to the "New:" list.
Lesson: z-design/prove-specs-pass-on-a-prototype
Erred: z-design
Upstream: none

### F6 [low] The Checked list is out of order and has two AC1 bullets, so the trace's ids will not match `check.sh`'s labels
Where: Acceptance criteria, Checked (the bullets run AC1, "AC1 adds", AC2, AC4, AC3); `check.sh:3` ("in the same order as the issue doc") and its four `check` lines
Evidence: `trace.deriveClaims` on the document gives `c0458:AC2` to the "AC1 adds" bullet, `c0458:AC3` to the walk criterion (`check.sh`'s AC2), `c0458:AC4` to the publisher criterion and `c0458:AC5` to the docs criterion (`check.sh`'s AC3). The reader renumbers a bullet whose number was already used (`trace.luau:435-439`). The second AC1 bullet predates round 4; the new AC4 bullet was put before AC3.
Critique: the final reviewer fills one trace row per claim id and cites the check that proves it. With these ids, row AC3 is proved by the check labelled AC2.
Consequences: none beyond the renumbering. Test plan lines that say "-> AC1" and "-> AC2" keep their meaning once the bullets are unique.
Recommendation: fold the "AC1 adds" sentence into the AC1 bullet and put the AC3 bullet before AC4. Rerun the reader: the ids are then AC1 to AC4, as in `check.sh`.
Erred: z-design
Upstream: zz-review

### F7 [low] The skills that restate the Level line and the raise are not in the list of what changes
Where: Checklist answers, **Restated rules**; Design item 4; Implementation step 9's sweep; `z-nile/skills/zz-rules/SKILL.md:185`, `z-nile/skills/z-design/SKILL.md:61`, `z-nile/skills/zz-review/SKILL.md:138`
Evidence: `zz-rules:185` says "A review line `Level: normal` or `Level: risky` says the ticket is not easy: the walk and `done` refuse it as light and it goes through the full path (`./zn stop <R-id>`, z-design in full, z-raft, ready)". `z-design:61` and Final mode item 4 say the same in their own words. After this ticket three things differ:
- in a raft of several the line is `Level: <ticket> <level>`, and a bare line stops the walk;
- `stop` empties the raft and the other members are rafted again;
- a ticket raised to normal needs no design review.

Item 4 lists what each skill loses and gains and names none of this. Step 9's sweep has no `Level` word, and `docs.spec` pins none of it. Only `work.finalBrief` tells the reviewer the new form.
Critique: a final reviewer who follows the skill writes a bare line in a raft of several, and the walk stops until someone edits the review. The final review is capped at one to three rounds after this ticket, so the mistake is costly.
Consequences: none. The three files are already in Touched modules.
Recommendation: add to item 4 that the three passages state the new line form, what `stop` does for a raft of several, and that only a ticket raised to risky needs a design review. Add `Level:` to step 9's sweep. Pin one sentence in `docs.spec` (zz-review's Final mode names `Level: <ticket> <level>`).
Lesson: z-design/restated-rules-move-together
Erred: z-design
Upstream: zz-review

Verdict: changes
