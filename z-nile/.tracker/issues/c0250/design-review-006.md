# Review 006: c0250 (design mode)
Inputs: prep worktree `prep-c0250-r2` at 6a11ed316 (`git diff origin/main -- z-nile/.tracker/issues/c0250 z-nile/skills`: `c0250.md`, `check.sh`, `guesses.md`, the `block-resolve`, `dispatch-block`, `docs` and `work-board` specs, design-refute-003/004/005); `z-nile/tests/lib/fakecli.luau` (modes `script`, `questions`, `author`, `ok`); main's `dispatch.luau` (`next`), `dispatcher.luau` (the step's cwd, `worktree`), `work.luau` (`claimable`, `skipped`, `queue`, `forRaft`, `decide`), `readycheck.luau` (`reason`), z-work and z-design SKILL.md; c0256's `step.spec` and `experiments/prototype.patch` (one-step guard, nested stop, the re-run prompt forms) on origin/main; c0248's re-prep in `prep-c0248-r2` (uncommitted `docs.spec`, `experiments/prototype.patch` z-work step 5 and zz-execute); `z-nile/tests/acceptance/f0399/docs.spec.luau`, `pick.spec.luau` and `done/f0399/f0399.md` (Problem, G8, G9); the specs that read `templates/prompt.md` (`c0117/docs`, `c0120/docs`, `c0111/skill-docs`). Prototype `proto-c0250-r2` read only for orientation (being rebuilt; E7 not raised).

Round 4 of the back-and-forth (the re-prep's fourth review), narrow as briefed. The answers to reviews 003 and 004 still hold as written. Of review 005's answers, F2 (f0399/docs on Overrides, AC13 and E7 (8)), F3 (`resolvedBy`, the one-step `z-raft c0110` case kills the `blockedBy`-only mutant), F5 (R0090 on `R0090/1/c0340` kills the current-branch mutant: it would give `Layer: c0340`), F6, F7 (the template sentence is a substring beside c0248's; no promoted spec pins the template whole), F8's prompt half and F9 hold. The round 2 and 3 cases run in their fixtures as far as main and c0256's patch show: the `script` mode passes `$id`, `$step` and `FAKE_DIR`; c0256's one-step guard sits in `oneStep`'s body before `modelStep`, so a blocked check beside it comes before the `zz-review` main-checkout error; `work queue` prints `<R>: <oneReason>`; the raft fallback pin is reached because `next` tests `openHuman` before any kind. Five gaps follow.

### F1 [high] Review 005 F1's answer settles a conflict between two captured outcomes with a guess, which may not shrink a captured outcome
Where: guesses.md G5; c0250.md Design 6 ("So in guess mode the capture's wall 'an ambiguity only the human can settle' is a recorded guess, … `needs-decision` blocks it only under `./zn dispatch`"); the Idea ("A worker that hits a wall it cannot get past never guesses. It escalates formally to the human."; the walls list "an ambiguity only the human can settle"); design-review-005 F1's Consequences and Recommendation; f0399.md:36 (captured: "z-work records every guess and assumption it makes") and its G9
Evidence: review 005 F1 said the guess-mode reading of the ambiguity wall "needs a `Decided with the user` line quoting f0399's ruling, or a bullet under `## Open to the human`". The answer records it as **Guess (prep) G5** and says "no captured outcome shrinks". It does: for a z-work session (the primary worker, per AGENTS.md) the confirmed Idea's "never guesses … escalates formally" becomes "guesses", and an ambiguity only the human can settle no longer escalates at all. f0399's own G9 and z-design's guess rules forbid a guess that drops or shrinks a captured outcome, and zz-review's design mode lists "a guess that drops or shrinks a captured outcome" as a finding. The two captures (c0250's, confirmed 2026-11-11, and f0399's, landed 2026-11-17) disagree, and only the user settles that.
Critique: the tempting fix is to add a `Decided with the user` line quoting the user's 2026-11-16 words in f0399 ("make guesses … I'll review them all before approving"). Those words were said about f0399's own design, not about c0250's wall.
Consequences: option (b) below changes f0399's landed step 5 and z-work's Guess mode. That means f0399/docs.spec's "no rule against guessing a human decision" and its Guess mode pins are overridden, and a guessed ruling and a block would sit in the same session. Option (a) leaves every pin as it is now.
Recommendation: escalate to the user: add `## Open to the human` F2 quoting both captured lines, with the options (a) "in guess mode an ambiguity is a recorded guess, as f0399 rules; c0250's 'never guesses' holds under `./zn dispatch` (the design as it stands, G5 the recommendation)" and (b) "z-work blocks with `needs-decision` on an ambiguity only the human can settle, in guess mode too (f0399's step 5 and Guess mode change; `f0399/docs.spec` joins Overrides for it)". Correct G5's "no captured outcome shrinks". If the user rules (a), the ruling becomes a `Decided with the user` line in the Problem.
Lesson: z-design/restated-rules-move-together
Erred: z-design
Upstream: none

### F2 [medium] Row "a carried question's `step:` is the model step the item resumes with" names a case that cannot fail for its mutant
Where: Rules and mutants row "a carried question's `step:` is the model step the item resumes with | dispatch-block :: AC8 a resolved raft's z-run… | `step:` the chain's next step (`z-ready`)"; dispatch-block.spec:789-814 (`ready R0010` by hand after the resolve, then `dispatch R0010`); design-refute-004 F2 ("the z-ready-in-the-chain path is covered by the same rule (reasoned)"); Design 5 rule (b) ("never a script step")
Evidence: the case readies R0010 by hand before the dispatch, so `dispatch.next` on the active raft returns `z-run`. A mutant that writes `step:` from the chain's next action also writes `step: z-run` and passes. The other carry cases cannot catch it either: c0070's chain goes next to `z-design` (a model step), and c0080 and c0110 are one-step runs of model steps. No case has a script step (`z-ready`, `raft-plan`) next at the carry, which is the only state the rule exists for.
Critique: the tempting fix is to mark the row reasoned. The mutant is cheap to kill.
Consequences: a chain that goes through `z-ready` needs c0050's approval to hold under `./zn dispatch` (f0399's `requireApproval`). The fixture then seeds `approval.md` with the contract hash, as block-resolve's fixture does, and the case pays one more script step.
Recommendation: one of these. (1) In the resolved-raft case, leave R0010 `prepared` after the resolve, with c0050's approval seeded so the dispatched `z-ready` passes, run `./zn dispatch R0010` on the fresh host, and assert `step: z-run` and "The last file is an answer". (2) Name the choice as a pure function (for example `dispatch.resumeStep(f)`: `z-run` for a `prepared` raft, `z-raft` for an issue with `resolvedBy`, `z-design` for a `new` issue), pin it in the AC8 pure block, and add it to the Public surface. Either way, re-point the row.
Lesson: z-design/spec-design-correspondence
Erred: z-design
Upstream: zz-review

### F3 [medium] Review 005 F4's answer leaves out the nested stop, which under c0248 names a layer's issue that `block` refuses and the wrong folder for the note
Where: Design 5 ("A nested step … its stop message tells its author to write `escalation.md` and run `./zn block <id> <reason>`"); Design 5's first bullet (the quoted prompt sentence without `--layer`); design-refute-005 F4 (lists the Headless, zz-execute, zz-review and z-work texts and the fallback, not the nested stop); dispatch-block.spec:406-420 (the only pin: issue c0020); c0248's re-prep docs.spec ("`./zn dispatch zz-review <issue-id> --mode code` (the layer's issue id)")
Evidence: review 005 F4 asked for "the nested stop when the id is a raft". The answer and the document leave it out. Under c0248, a readied raft's layer review is dispatched with the layer's issue id, so the nested review's `{id}` is an active member such as c0210. The stop then tells the author to write `escalation.md` in c0210's folder and run `./zn block c0210 <reason>`. `block` refuses that ("c0210 is in R0010, readied: block the raft: …"). The command the refusal names then finds no note in the raft's folder, because the author wrote it in the issue's folder. That is two refusals on the main path a dispatched z-run takes when its reviewer needs the user.
Critique: the tempting fix is to rely on `block`'s refusal. It fixes the command but not where the note was written.
Consequences: the stop has to read the item's raft (the dispatcher already reads `raft:` for a stream review). For an issue in an active raft it names the raft's folder and `./zn block <R> <reason> --layer <issue>`; for an issue in design or a draft raft it stays as it is.
Recommendation: specify that rule in Design 5 and update its quoted prompt sentence to the pinned text. Pin it in dispatch-block with a nested `zz-review c0050 --mode code` started from a `script`-mode z-run on readied R0010, asserting `./zn block R0010 <reason> --layer c0050` and the raft's folder. Add a row (mutant: the nested stop names the issue id).
Lesson: z-design/restated-rules-move-together
Erred: z-design
Upstream: none

### F4 [low] Design 6 says step 5 replaces "only its tail", but the pinned string also drops `<R>` and cannot keep c0248's sentence where c0248 puts it
Where: Design 6 ("replacing only its tail … so that f0399's first sentence and its last and c0248's pinned sentence … stay"); docs.spec's step 5 pin ("… Tell the person, then run `./zn work next` again. Never narrow scope to get green."); c0248's prototype.patch:2714 ("… run `./zn work next <R>` again. A blocked layer stops the layers above it, and `./zn done <R> --through <issue>` lands the green layers below it. Never narrow scope to get green.")
Evidence: c0248 puts its sentence between "again." and "Never narrow scope to get green.", and c0250's pin needs those two sentences next to each other. Replacing only the tail, as Design 6 says, turns docs.spec red. The pin also changes "`./zn work next <R>`" to "`./zn work next`", which is outside the tail. Both specs pass only if c0248's sentence moves after "Never narrow scope to get green.", and neither document says so.
Critique: none beyond the executor's first red run.
Consequences: none for the code.
Recommendation: Design 6 states the result: c0248's sentence follows "Never narrow scope to get green." (or the pin is split in two at "again." so c0248's sentence keeps its place), and the `<R>` drop is intended (the blocked raft is no longer the session's).
Erred: z-design
Upstream: none

### F5 [low] An `abort` resolution is never carried, but the read-the-note sentence still sends every later step to it
Where: Design 5 ("A resolution whose decision is `abort` is never carried … its next step starts fresh"); READ_NOTE in z-design, z-raft, z-work and zz-execute ("When the item's folder holds `escalation.md` with a `## Resolution`, read it before you start: it is the human's decision on the last block."); the note stays until the next block archives it
Evidence: the human aborts c0010 (it goes back to `new`) and later restarts it. The dispatcher adds nothing, but the dispatched z-design reads its skill. The skill sends it to `escalation.md`, which still says `Decision: abort`, described as "the human's decision on the last block". The step can read that as an order to stop. The chain then stops on "z-design ended but c0010 is still new".
Critique: F8's answer changed the dispatcher's rule and not the sentence that repeats it.
Consequences: none beyond one clause.
Recommendation: READ_NOTE says "unless its `Decision:` is `abort`: that attempt ended, start fresh" (docs.spec pins the clause), or `resolve … abort` archives the note as `escalation-NNN.md` in its commit (the publish rule already allows a note to move to an archive). Add a reasoned row.
Lesson: z-design/restated-rules-move-together
Erred: z-design
Upstream: none

### F6 [low] Two records lag the answers: a stale row and the Affected specs list
Where: Rules and mutants row "the Layer comes from tracker state | block-resolve :: AC4 block on an active raft… (the checkout on layer 1) | the Layer read from the current branch | run (b63d94f5)"; Affected specs
Evidence: (1) That case now passes `--layer c0210`, so a mutant that reads the current branch only when `--layer` is missing passes it. The new row for the R0090 case covers the rule, and the old row still claims a run on a case that changed. (2) review 005 F2 recommended adding `f0399/docs.spec` (and the fast `f0399/pick.spec`) to Affected specs. They are on Overrides and in AC13's list but not under Affected specs.
Critique: none.
Consequences: none.
Recommendation: drop the old row, or narrow its mutant to "the current branch read even when `--layer` is given"; list both f0399 specs under Affected specs.
Erred: z-design
Upstream: none

Verdict: changes
