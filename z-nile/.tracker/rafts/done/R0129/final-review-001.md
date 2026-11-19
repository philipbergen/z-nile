Reviewer: claude-opus-5-5

# Review 001: R0129 (final mode)
Inputs: layer R0129/1/f0399, top layer's finished commit 93bfb1a88 (the trace's `Commit:`), head 9112e2062 (the skeleton); `git diff origin/main...HEAD` (merge base 9e7906b35, origin/main fetched at the start of the review); `./zn capture f0399` (capture commit 093f7c262, no marker); f0399.md, its `check.sh`, the six specs in `acceptance/`, `guesses.md`; R0129.md (its `## Open to the human`: S1 ruled, F4 guessed), its `check.sh`, `review-001.md`, `refute-001.md`; `trace.md` (the skeleton, filled by this review).

### F1 [high] `./zn trace R0129 --check` fails: origin/main moved during this review, so the stack is not on main's tip
Where: z-nile/.tracker/rafts/active/R0129/trace.md:3 (`Commit:`); the check's output.
Evidence: while this review ran, origin/main moved from 9e7906b35 to 9dc856511 (R0120 landed, "R0120: bind f0186", 2026-11-17 16:16 PST; then "tracker: ready R0125"). `./zn trace R0129 --check` on the filled table prints `row Commit, commit: table is stale (R0129/1/f0399 is not stacked on the layer below)`, then `did not run green for this stack` for every cited `check.sh` line (the layer does not count as finished on the new base), then eleven `pickman/src/...` files as `changed source file missing from table` (R0120's files, seen because the layer's base is no longer main's tip). Before main moved, the only problems the check named were the empty cells. No commit came after the table.
Critique: no step erred: main moved under a finished stack. The tempting fix is to add the pickman rows to `## Source files`; they are not this raft's files.
Consequences: a restack rebases the one layer and gives it a new finished commit, so the `Commit:` line changes; the cells cite file:line in files the restack does not touch (main's commits are tracker and pickman files), so they should stand, but every `main.luau` line number must be re-checked if a merge lands in that file first.
Recommendation: `./zn restack R0129` (Phase 5 step 2), `./zn trace R0129` for the new `Commit:` line, carry this table's rows into it unchanged, and run `./zn trace R0129 --check` until it passes. Run `./zn check f0399` once on the restacked layer.
Erred: none
Upstream: none

### F2 [medium] A held raft readied `--on` an unlanded raft is resumed in tier 1, ahead of tickets with nothing unmet
Where: z-nile/engine/work.luau:700 (the `done`/`build` loop of `work.decide`); z-nile/.tracker/issues/active/f0399/f0399.md:183 ("Tier 1, nothing unmet"), :184, :185, :177 ("a raft has one when any member has one outside the raft").
Evidence: the loop takes any active raft this author holds that is free, whatever its `on`. A pure probe run with `./zn run --time 60` on `work.decide`: R0030 active, held by this author, `on = "R0005"`, `onLanded = false`, its member c0030 depends on c0005 (active in R0005), layer 1 not started; R0040 a backlog raft `ready` accepts. Output: `picked R0030 implement: Resuming R0030: you hold it and no live session carries it. c0030 has no layer yet. Run ./zn start R0030 and ask again.` R0040 has nothing unmet and R0030 has an unmet dependency, so the capture's S2 ("the tier always wins: every ticket with no unmet dependency comes before any ticket that has one") and S5 are not met for this case. The design's own definition (f0399.md:177) puts R0030 in tier 2, but tier 2 (f0399.md:193 to :195) lists no resume of a held raft, and lines 184 and 185 do not exclude one. pick.spec has no case with an active raft whose `on` has not landed in the unnamed order (only the named `wait` at pick.spec.luau:401).
Critique: the design missed a state its own `--on` creates, and the code followed lines 184 and 185 literally. The tempting fix is to skip such a raft in tier 1, which leaves it never resumed unnamed: that drops S1's "picks any ticket that is not landed and does its next step" for it.
Consequences: moving it changes the order the person approved, so f0399's Design section 4 changes (a material change: the approval stops holding, which it already does for `guesses` since G1). In tier 2 the raft is furthest along, so it goes first there, before `ready --on`. Its `done` pick is unaffected: `work.forRaft` already gives `wait` while `on` has not landed (work.luau:393). A raft whose base has landed (`onLanded`) is in tier 1 as now. The carriers rule (`work.free`) applies unchanged.
Recommendation: in z-design (or as a recorded `--step build` guess, then the design text): tier 1's lines 1 and 2 take only a raft with no `on`, or whose `on` has landed; tier 2 gains, as its first line, "resume: an active raft this author holds, free, built on an unlanded raft, whose next action is a build action". In `work.decide`, filter the existing loop on `not r.on or r.onLanded` and run the same loop for the others at the head of tier 2. Spec cases in the ordinary `work.spec`: R0030 (held, `on` unlanded, `implement`) and R0040 (backlog, ready) give `ready R0040`; R0030 alone gives `Resuming R0030`; R0030 with `onLanded = true` beside R0040 gives the resume.
Erred: z-design
Upstream: zz-review

### F3 [low] AC4 orders an issue's `fix` before `rafting`; the Design, the spec and the code put `rafting` first
Where: z-nile/.tracker/issues/active/f0399/f0399.md:712 ("then a raft or issue to fix, a prepared issue to raft"); f0399.md:188 and :189 (5 rafting, 6 fix); z-nile/.tracker/issues/active/f0399/acceptance/pick.spec.luau:242 ("an unsized prepared issue: after an issue that can be rafted"); z-nile/engine/work.luau:765.
Evidence: with c0031 prepared and unsized and c0035 prepared and sized, AC4's sentence reads as c0031 (`fix`) first; the code and the pinned case pick c0035 (`rafting`).
Critique: the criterion the person approves says something the build does not do. The tempting fix is to change the code to match the sentence, which breaks the pinned case.
Consequences: none beyond the wording; the Design's order is the one the spec pins.
Recommendation: in z-design, reword AC4 to "then a raft to fix, a prepared issue to raft, a prepared issue to size, a design of this checkout to resume and an issue to design". The approval is renewed anyway (F2, G1).
Erred: z-design
Upstream: none

### F4 [low] A finished layer and the trace accept a committed `approval.md` or `guesses.md` of any issue, not only the raft's members
Where: z-nile/engine/layergit.luau:266; z-nile/engine/trace.luau:462 (used at :475 and :502); f0399.md:132 ("in any issue's folder").
Evidence: both match `/issues/active/<any id>/(approval|guesses).md` and `/issues/<any id>/...`. A `./zn guess c0123 ...` in this worktree for an issue outside R0129, committed on the layer after finish or after the table, leaves the layer finished and the trace passing, and lands with R0129, changing c0123's contract on main. It fails safe (c0123's approval then stops holding), so nothing unapproved lands.
Critique: the trace is meant to account for every file in the stack, and this lets a non-member's contract file ride along unaccounted for. The tempting fix is to drop the allowance, which turns E3's fallback off and unfinishes a layer on every approval.
Consequences: restricting it to members needs the member list where both functions run: `isPostFinishPath` has `raftId` (its members are `store.members`), and `isTrackerFileOf` already has `issues`.
Recommendation: accept the two files only for the raft's members, in both places; one case each (a member's `guesses.md` after finish keeps the layer finished; another issue's does not).
Erred: z-design
Upstream: none

### F5 [low] f0399.md's "Open to the human" says `none` and is followed by two Verification log entries
Where: z-nile/.tracker/issues/active/f0399/f0399.md:772 to :776.
Evidence: `## Open to the human` / `none` / then `- 2026-11-17 (after the redesign): ...` and `- 2026-11-17 (code review 001): ...`, which are verification results (check counts, gate runs). `openlist` ignores them (no `F`/`JC` id), so no gate is affected.
Critique: the person reads this section to decide; "none" followed by bullets reads as open items, and the Verification log at line 743 lacks the last two entries.
Consequences: none.
Recommendation: move both bullets under `## Verification log` (Phase 5 step 1's final entry), leaving `none` alone under `## Open to the human`.
Erred: zz-execute
Upstream: none

## What was checked
- **Idea = design.** The capture (093f7c262) and the document's Problem, Non-goals and Solution are word for word the same (f0399.md:19 to :38). Each Solution line has a Design section and a criterion; the two narrowings (S6's prep from main with prototypes on the dependency's branch, G11; S7 only within one type and project, G12) are recorded guesses the user approved on 2026-11-17 (R0129.md:26). S2 and S5 are not met for one state (F2).
- **Design = code.** I read the whole engine diff (approval, contract, guesses, layergit, main, openlist, raftplan, readycheck, readyfacts, sessionread, trace, work, workread, cachepaths). Every Design section has its code; the deviations the Verification log names (f0399.md:763 to :770: trace.luau for E3, the `f0399` helper table, valued flags for `guess --open`, `sessionread.id`, `openlist.guessedWords`, `readycheck.guessedProblem`, the restack order for an `--on` raft) are local and recorded. `dispatcher.luau` and `dispatch.next` are not in the diff. Review 001's fixes are in the code (deps at main.luau:4530, the release rule at z-work step 6, the `you hold` note at work.luau:727, sessionread's dotted folder at sessionread.luau:261, AGENTS.md's `.cache/work/`). The squashed 93bfb1a88 holds the same engine, spec and skill changes as the reviewed 1c28f9fee apart from main's `--unattributed` flag and the lesson files (compared line by line).
- **Design = test.** At this head the four pure specs pass when run by name: guesses 9/9, pick 17/17, plan 6/6, docs 6/6. `land.spec` and `on.spec` rest on the Verification log's 18/18 at 1c28f9fee and the code review's 18/18; I did not rerun `./zn check f0399` (several minutes; no finding depends on it, F1 asks for it after the restack). Sequestration: the only change under `acceptance/` or a `check.sh` is the generated `acceptance/watch.txt`.
- **Open to the human.** S1 carries a ruling. F4 carries `Guessed (agent, 2026-11-17): f0399 G1`, and G1 is in guesses.md (refuted F4 recorded as a build guess). That guess was added after the approval, so `./zn approve f0399 --check` says `contract changed since approval: guesses`: R0129's ready commit (cb4e7ccec) has no `Lands:` trailer, so `done` applies today's rule and will refuse until the person runs `./zn approve f0399` on the top layer. That is the intended pause, not a defect.
- **Repository safety and bounded commands.** The new real-git specs work in `.cache` fixtures; `workread.carry` writes only `<main checkout>/.cache/work/carriers.tsv`, allowed in cachepaths.luau:167. My one probe ran under `./zn run --time 60` from a `.cache` folder that I removed afterwards.

Lesson candidates for the lead:
- z-design: a design that adds a new kind of state (a raft built on an unlanded raft) must place that state in every ordered list it already wrote, by the list's own definitions. Check: for each new state the design creates, which line of each ordering, refusal list and reason list takes it, and does the line's header still hold for it? (F2)

Verdict: changes
