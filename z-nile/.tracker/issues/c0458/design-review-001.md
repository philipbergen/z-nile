# Review 001: c0458 (design mode)
Inputs: prep worktree `prep-collapse-reviews-and-tighten-caps` at 1b78199b0 with its uncommitted `z-nile/.tracker/issues/c0458/{c0458.md,check.sh,guesses.md,acceptance/caps-modes.spec.luau,acceptance/walk.spec.luau}`; `./zn capture c0458` (Problem, Non-goals and Solution unchanged from the capture); `./zn promote-check c0458`; a scratch probe of `readycheck.reason` and `work.lightNote` run through `./zn run --time 60`; `z-nile/engine/{rounds,work,workread,readycheck,easy,light,dispatch,dispatcher,models,main}.luau`; `z-nile/check.sh`; greps of `z-nile/tests/acceptance`.

### F1 [high] The sequestered specs fail the type check they get once promoted, and one of the errors conflicts with the Design's signature
Where: `acceptance/caps-modes.spec.luau:22-24,27,59,60`, `acceptance/walk.spec.luau:63`; Design item 3 ("`work.lightNote` stays as the exported name so its callers do not move"); Unknowns & experiments, "Mutation check"
Evidence: `./zn promote-check c0458` prints seven type errors and ends "promoted acceptance specs would break tests/". The errors: `caps-modes.spec.luau(22,57)`, `(23,59)` and `(24,58)` "Expected type table, got 'unknown'" (`want[1]` in the untyped `for stage, want in {...}` loop); `(27,12)`, `(59,12)` and `(60,12)` "Function 't.expect' expects 0 to 1 argument, but 2 are specified" (`string.find` returns two values; it needs parentheses); `walk.spec.luau(63,31)` "Expected this to be 'string', but got 'RaftFact'". None of them is a require of a module the issue creates, which is the only failure z-design step 4 allows. The gate type-checks promoted specs: `z-nile/check.sh:140` puts `z-nile/tests` in `LUNE_DIRS`, and `:294-295` runs `luau-lsp analyze` on it, ignoring only `.tracker`. The last error is a design conflict, not a typo. The only caller of `work.lightNote` is `dispatch.luau:268`, which passes `p.id`, a string, and `work.lightNote = lightText` takes `id: string` (`work.luau:346,354`). The spec passes a `RaftFact`. Design item 2 also leaves open whether `RaftFact.codeReview` "stays ... only if a reader still needs" it, and the spec's typed `work.RaftFact` literal sets `codeReview = "none"`. If the executor drops the field, that literal is a second type error in a file it may not edit.
Critique: the sequestered files cannot change during execution, so the raft cannot pass the gate at `done`'s promotion. The executor would have to escalate, or change `lightNote`'s signature against the Design. The fix the author will be tempted to make is to add parentheses and an annotation and stop there. That leaves the signature and field questions open.
Consequences: whichever signature the Design picks, the spec and `dispatch.luau`'s caller must agree with it. If `lightNote` takes a `RaftFact`, the dispatcher has no `RaftFact` at `dispatch.luau:268` and needs one built, or a second function. If `codeReview` leaves `RaftFact`, every tooling spec literal that sets it changes too (14 files list it: `grep -rln codeReview z-nile/tests`).
Recommendation: fix the three typing slips. Decide in the Design, in one sentence, the exported brief's signature: for example keep `work.lightNote(id: string): string` and have the spec call `work.lightNote("R0304")`. Also decide whether `RaftFact.codeReview` stays (as an optional field the walk ignores) or goes. Make the spec's literal match that decision. Rerun `./zn promote-check c0458` to zero errors and record the result. As the lesson asks, run both specs green against a scratch prototype of at least `work.luau`, `rounds.luau`, `dispatch.luau`, `models.luau` and `readycheck.luau`, and kill each listed mutant there. The Design's "every row is reasoned" does not stand in for that run when the modules already exist.
Lesson: z-design/prove-specs-pass-on-a-prototype
Erred: z-design
Upstream: none

### F2 [high] AC6 (AC2) is passed by an implementation that keeps today's light brief, which drops seven of the Code mode checks the Non-goals keep
Where: `acceptance/walk.spec.luau:59-64` (AC6); Rules and mutants row "the final brief carries the Code checks for every raft"; Non-goals bullet 3; Solution bullet 3
Evidence: today's `lightText` (`work.luau:347`) already contains every needle AC6 looks for: `git diff origin/main...HEAD`, `Overrides`, `repository safety`, `Judged` and `design`. A probe confirms that `work.lightNote(<any table>)` returns it unconditionally today (`lightNote(table) has Overrides: true`), so the spec's last assertion can never fail. Take this mutant: delete the `codeReview` branches and make `lightNote(r)` return the unchanged `lightText` for every raft. It passes AC5 and AC6. Its brief still says "apply zz-review code mode's checks too (correctness, regressions and the Overrides check, repository safety, bounded commands)". Sequestration, Weak tests, Design adherence, Architecture rules, Performance, Lessons and the ruling-line check 11a are not named. A normal or risky raft gets those checks only from the per-layer review this ticket removes. The brief would also still say "This raft took the light path ... ONLY review" for every raft.
Critique: Non-goal 3 ("does not drop any item of zz-review Code mode") and Solution bullet 3's list of thirteen items are this ticket's safety claim. No check pins them. The tempting fix is to add a few more needles. A needle list that is not the whole Solution list is still passed by a brief that drops the rest.
Consequences: pinning every item name in the brief fixes the wording of each item. The Design must give the exact item names the brief uses, the same names as zz-review's section (F6), so the two cannot drift. The case must also run on a raft that is not light and has several tickets, because "for every raft" is the claim.
Recommendation: AC6 asserts that `d.why` contains each of the thirteen item names of Solution bullet 3, for a raft of three tickets with `light = false` and for a light one. It asserts that neither contains `took the light path` or `ONLY review`. It also asserts that the brief names judging the design of a ticket with no passing design review, and the `Level:` line. Replace the `work.lightNote(...)` assertion with one that can fail: the text the dispatcher's prompt gets, for a raft that is not light, contains the same thirteen names (see F7). Add the subset-brief mutant to Rules and mutants and kill it on the prototype (F1).
Lesson: z-design/spec-design-correspondence
Erred: z-design
Upstream: none

### F3 [high] The Overrides line misses at least four promoted specs that the zz-review and dispatch changes turn red
Where: Regression guard, `Overrides:`; Design items 4 and 5
Evidence: Design item 4 renames `## Code mode (one layer)` to `Code checks (applied by Final mode)` and deletes `## Stream mode`. These specs then go red:
- `z-nile/tests/acceptance/c0191/docs.spec.luau:114-122` requires both `## Stream mode` and `## Code mode` in zz-review, and asserts `t.expect(design ~= nil and stream ~= nil and code ~= nil ...)`.
- `z-nile/tests/acceptance/c0043/review-skill.spec.luau:48` calls `section(REVIEW, "Code mode")`, which `assert`s that a section starting `## Code mode` exists (`:12-17`).
- `z-nile/tests/acceptance/c0119/scope-docs.spec.luau:147` makes the same `section(..., "Code mode")` call.

Design item 5 makes `--mode code` die at "zz-review has no mode". `z-nile/tests/acceptance/d0415/dispatch.spec.luau:227-235` runs `./zn dispatch zz-review c0010 --mode code` and asserts the output has "there is no further round", so it goes red too. None of these four is named. The Design's re-derivation command (`grep -rlnE "code-review|stream" z-nile/tests/acceptance`) misses the three heading pins, because they match `Code mode`, not `code-review`. Three more specs exercise modes or files this ticket removes or stops writing, and none of them is named or ruled out: `d0415/filing.spec.luau:115-160` (`dispatch.filing` with modes `code` and `stream`), `c0045/workstreams.spec.luau` and `c0136/*.spec.luau` (`stream-review-*`).
Critique: an unnamed override is high by rule (zz-review Design mode item 4). The executor will find these as red specs at the gate, mid-raft, with no ruling on what each narrows to. The tempting fix is to append the four names. The list would still rest on a grep that misses heading pins.
Consequences: renaming the zz-review heading reaches every spec that slices that skill by heading. A heading that keeps the prefix `Code mode`, for example `## Code mode (the checks Final mode applies)`, would keep `c0043` and `c0119` green. `c0191` still needs `Stream mode`. That makes the heading text itself a design decision.
Recommendation: name each of the four specs in `Overrides:` with what it pins afterwards (`c0191` AC6: Bounded commands in Design mode and in the Code checks, with no Stream mode). Alternatively, choose a heading that keeps `## Code mode` as its prefix and say that `c0043` and `c0119` then stay unchanged. Settle `d0415/filing`, `c0045/workstreams` and `c0136/*` by name: overridden, or stays green and why. Confirm the list with a run of the whole suite on the prototype F1 asks for, not by grep alone. Extend the re-derivation command with `"## Code mode"`, `"## Stream mode"`, `"Code mode"` and `"--mode", "code"`.
Lesson: z-design/confirm-overrides-with-a-suite-run
Erred: z-design
Upstream: none

### F4 [high] The captured outcome that the final review "may raise the ticket's level" for any ticket with no passing design review has no design and no criterion, and the engine reads a `Level:` line only for a light raft of one ticket
Where: Solution bullet 5 ("... and it may raise the ticket's level with a `Level:` line as the light path allows today"); Design items 2, 3 and 8; Acceptance criteria
Evidence: the raise is read only for a raft whose ready commit claimed the light path. `workread.luau:433-437` computes `raisedTo` only `if marked`. `./zn stop` acts on a raise only when `raised ~= nil and #ids == 1` (`main.luau:7265`). `./zn done` refuses on it through `lightgit.of(raft)` (`main.luau:5473-5483`). Take a raft of three tickets: one easy, one normal with no design review, one normal with one. Its final review writes `Level: risky` about the normal ticket's design. Nothing reads that line: the walk goes on, `done` lands the ticket as normal, and the ticket that needed a design review never gets one. A raft of several tickets also has no way to say which ticket a `Level:` line raises. The texts that say what a raise leads to are also wrong under the new rules: `light.luau:314` and `main.luau:5481` say "z-design in full (every section, ..., size and a design review)", but a ticket raised to `normal` no longer needs a design review. It could return from design with none and meet the same final review again.
Critique: this is a Solution outcome with no Design and no Checked criterion, which is high under zz-review Design mode item 11. The tempting fix is to compute `raised` for every raft. Without a per-ticket form and a new rule for what a raise does, that brings back the full-design detour, now with no design review at the end of it.
Consequences: the Design must decide three things. First, the form of a raise in a raft of several tickets, such as `Level: <ticket> <level>`, read by `easy.raised`. Second, what each raise does now: to `normal`, rerun the final review at the raised level (model and cap) or send the ticket back to design; to `risky`, a design review is required, so take that ticket out of the raft. Third, how `stop` takes one ticket out of a raft of several, and what `done` refuses. Each of these is a spec case.
Recommendation: add a Design item that covers the three decisions, and the wording at `light.luau:314` and `main.luau:5481`. Add `light.luau`, `lightgit.luau` and `easy.luau` to Touched modules. Add a Checked case in `walk.spec`: a raft of three tickets, not light, with a final review that raises one member. The walk stops with the decided action, and `done`'s refusal names the ticket. If the designer reads "as the light path allows today" as limited to one-ticket light rafts, the Recommendation is `escalate to the user:` with two options. Keep the full scope: every raft, at the cost above. Or record a `Scope decision (user, ...)` that limits raises to light rafts.
Erred: z-design
Upstream: none

### F5 [high] The mixed-raft rule (highest risk sets the final review's model and cap) has no Checked criterion
Where: Solution bullet 10 ("so a raft of one easy and two normal tickets gets one heavy review capped at 2 rounds"); Design item 7; Unknowns E3; Rules and mutants last row ("work-can :: mixed raft (executor)")
Evidence: the only case for this outcome is one the executor writes in `tests/tooling/work-can.spec.luau`. `check.sh` runs `caps-modes.spec` and `walk.spec`, and neither builds a mixed raft. AC4 pins the table and AC1 pins `rounds.max`. Neither pins that the level comes from the highest member. A wrong implementation passes `check.sh`. Example: the reworked `activityOf` or brief reads the level from `member.level` of the first ticket, or from the light path's easy level (`work.luau:1949-1957` picks among three sources).
Critique: a captured outcome left without an acceptance criterion is high under item 11, even though today's code (`rounds.highest`, `dispatcher.luau:1007-1008`) already does it. This ticket edits the code that decides it.
Consequences: a pure case needs the walk's level for a final-review decision. Through `work.activityOf(input, d)`, with a `RaftFact` whose `level` the reader computed, it tests only the walk. The reader's `rounds.forMembers` and the table lookup each need their own assertion.
Recommendation: add to AC4 (caps-modes) the following: `rounds.forMembers({"easy","normal","normal"}, 0)` is `normal`. The resolved `final-review` setting of the root `.models.toml` at that level is `heavy`. `rounds.max(rounds.DEFAULT, "code", "normal")` is 2. `work.activityOf` on a `final-review` decision for a raft with `level = "normal"` and an easy first member returns level `normal`. Name AC4 in the Rules and mutants row.
Erred: z-design
Upstream: none

### F6 [high] The skill outcomes have no criterion: zz-review keeps every Code check and loses Stream mode, and z-design requires a design review only for risky
Where: Solution bullets 3, 6 and 12; Design item 4; Acceptance criteria
Evidence: neither `check.sh` line reads a skill. A wrong implementation passes both ACs. Example 1: it deletes zz-review's Code mode section along with Stream mode, or keeps only the light path's five items in Final mode item 4. Example 2: it leaves z-design step 5 requiring a design review for `normal`. Today z-design's easy paragraph (`z-nile/skills/z-design/SKILL.md:61`) says "`ready` refuses an easy ticket with no design review unless it is light, and `./zn work next` answers `draft` for it". After this ticket the engine does the opposite, and no check catches a stale skill. The skill is what a dispatched or interactive reviewer follows, so a dropped item there is a dropped check, whatever the brief says.
Critique: these are captured outcomes with no acceptance criterion (item 11). They are not Judged: each one is a fact a docs case can read, as `c0117/docs.spec.luau` and `c0191/docs.spec.luau` already do. The tempting fix is to put them in Implementation step 9's sweep. A sweep is not a check.
Consequences: a docs case pins headings and item names. Pin the rule (each of the thirteen names appears under the Code checks heading, `## Stream mode` is absent), not the section's whole text, so later edits do not need an override (zz-test/promoted-specs-pin-rules-not-sets). The heading it reads is the one F3 decides.
Recommendation: add AC3 with a `docs.spec.luau` in c0458's acceptance folder. It checks that zz-review has the Code checks heading with each of the thirteen bold item names from Solution bullet 3 under it, and has no `## Stream mode`. It checks that Final mode points at those checks for every raft and has no "light path ... ONLY review" sentence. It checks that z-design step 5 requires a passing design review for `risk: risky` only and says a started review binds. It checks that z-design's easy paragraph no longer says `ready` refuses an easy ticket or that `work next` answers `draft`, and that zz-execute names no `--mode code` or `--mode stream`. Add the rows and run the mutants.
Erred: z-design
Upstream: none

### F7 [medium] The dispatcher's final-mode prompt keeps the brief behind the light-only gate, and the Design does not remove it
Where: Design item 3 ("The dispatcher's final-mode prompt (`dispatch.luau:283-286`) uses the same text"); `dispatch.luau:265-269`; `dispatcher.luau:337-345`, `:1052-1056`, `:2571-2587`
Evidence: the final-mode prompt appends the brief only `if p.light`, and `p.light` is `dispatcher.lightFinal(...)`, which is `verdict.light and not verdict.reviewed`. The lines the Design cites (`:283-286`) are the round-two text, not this prompt. Unless the Design names the gate, a dispatched final review of a raft that is not light gets no brief, the unattended path this ticket most affects. Two more places treat only the light path's final review as the only review. `dispatcher.resolve` guesses the builder's model only for `light == true` (`:1054`). The preflight message "light path: this final review is the only review" (`:2587`) also depends on the light path. No AC covers either.
Critique: an executor who follows Design item 3 as written changes the text and keeps the gate. Interactive runs then get the brief and dispatched runs do not.
Consequences: removing the gate makes `lightFinal` mean "the raft's only review", which is every final review. Then `resolve`'s builder guess applies to every raft, so a raft with no build rows gets a guessed `author` and `sameModel` stays nil. Its spec cases change with it.
Recommendation: in Design item 3, say `dispatch.luau:268` appends the brief for every `--mode final`. Either delete `lightFinal` and the `light` parameter of `resolve`, or rename them and give them a rule that holds for every raft. Fix the line citations. Add a case to `walk.spec` or `caps-modes.spec` (pure: `dispatch.prompt` for `zz-review` `final` with `light = false`) asserting that the prompt carries the thirteen names (F2).
Erred: z-design
Upstream: none

### F8 [medium] AC7's `ready` assertion only checks that a phrase is absent, so a reworded refusal passes
Where: `acceptance/walk.spec.luau:111` (`t.expect(has((readycheck.reason(r)), "no design review")).toBe(false)`)
Evidence: the probe shows that today `readycheck.reason(r)` on this fixture returns exactly "c0001 is easy with no design review, and it does not take the light path: ...". The case is red today. Now take a mutant that keeps the refusal at `readycheck.luau:235-241` and rewords it, for example "c0001 is easy and has no design-review file". It passes. So does a mutant that moves the refusal into another check. The test never shows that `ready` accepts the ticket, which is what AC2 says ("`ready` does not refuse it").
Critique: a negative text match passes with any wording that avoids the phrase. The tempting fix is a second phrase, which has the same weakness.
Consequences: asserting that `reason` is nil needs a fixture that every other readycheck rule accepts: guesses, the approval and the check.sh labels. Building it shows what else `ready` demands of an easy ticket off the light path, and some of it may also need this ticket's attention, such as an approval for a guessless ticket.
Recommendation: make the fixture valid apart from the removed rule, and assert `readycheck.reason(r) == nil`. Add a control case where the same raft with one rule broken (for example a `Level:` line holding a bad value) still refuses, so the nil does not come from an early return. Run both on the prototype.
Lesson: z-design/spec-design-correspondence
Erred: z-design
Upstream: none

### F9 [medium] AC2's spec pins the exact set of review modes instead of the rule
Where: `acceptance/caps-modes.spec.luau:31-37` (`t.expect(keys).toEqual({ "design", "final", "raft" })`)
Evidence: the outcome is that `code` and `stream` are refused and that `design`, `raft` and `final` still work. The case asserts that no other mode exists. A later issue that adds a review mode would then have to override c0458's promoted spec, although nothing this ticket decided changes.
Critique: this is the defect the lesson names. The tempting fix is to delete the set assertion, which loses the "only" in the Solution. The rule-shaped assertions that follow it already carry that.
Consequences: none beyond the case. The `pcall` refusals of `code` and `stream`, and the three `activityFor` positives, already pin the rule.
Recommendation: replace `toEqual` with assertions that `REVIEW_MODES.code` and `REVIEW_MODES.stream` are nil and that `design`, `raft` and `final` are present.
Lesson: zz-test/promoted-specs-pin-rules-not-sets
Erred: zz-test
Upstream: z-design

### F10 [medium] Touched modules leaves out files the Design edits and the issue's own specs
Where: Design, Touched modules
Evidence: Touched modules does not include these paths:
- The issue's own acceptance folder (`z-nile/.tracker/issues/c0458/acceptance`), which the template says to include.
- The skills that "Restated rules" lists: `zz-stats`, `zz-test` and `z-raft`.
- `z-nile/app/index.html` and `z-nile/go` (E2 and step 9).
- `light.luau`, `lightgit.luau` and `easy.luau` (F4), and `dispatcher.luau`'s `lightFinal` (F7). `dispatcher.luau` itself is listed.
- The promoted spec folders the Overrides line changes beyond `c0117` and `c0111`: `c0136`, `c0118` and `f0399`, plus F3's `c0043`, `c0119`, `c0191` and `d0415`.
Touched modules feeds `lune run z-nile/affected` and spend attribution, so the 332-line affected list and the ledger both miss these files.
Critique: an executor who scopes the work from this list skips files that hold the old rules. The selector also skips specs that pin them.
Consequences: adding the spec folders widens `--affected` runs during execution, which is the point.
Recommendation: add every path above. Rerun `lune run z-nile/affected -- <paths>` and record the new count.
Lesson: z-design/restated-rules-move-together
Erred: z-design
Upstream: none

### F11 [low] Two factual slips in the Design's text
Where: Checklist answers, "Existing work"; Design items 3 and 5
Evidence: "Existing work" says a `.models.toml` that still holds `[roles.code-review]` fails the parse "(an unknown activity)". `models.parse` checks the names under `[activities.*]` (`models.luau:576`) but does not check role names against `ROLE_OF` (`:760-840`). So only `[activities.code-review]` fails, and a leftover `[roles.code-review]` parses silently. For example, `d0415/dispatch.spec.luau:37` keeps one. The dispatch line citations are also off: `:283` and `:283-286` are the round-two text and the `kind` line, not the stream branch (`:258-264`) or the final prompt (`:265-269`).
Critique: an executor who trusts "fails the parse" expects other sessions' leftover tables to be caught. A role table naming a removed activity is dead config that nothing reports.
Consequences: none, beyond deciding whether a leftover role table should be reported.
Recommendation: correct the sentence: only `[activities.code-review]` fails the parse, and `[roles.code-review]` is ignored. Optionally add a refusal of roles not in `ROLE_OF`, as a Design line with a case. Fix the line citations.
Erred: z-design
Upstream: none

Verdict: changes
