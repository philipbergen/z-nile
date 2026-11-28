# Review 008: c0458 (design mode)
Inputs: prep worktree `prep-collapse-reviews-and-tighten-caps` at d72937d50 with its uncommitted `z-nile/.tracker/issues/c0458/{c0458.md,check.sh,guesses.md,harvest.md,acceptance/{caps-modes,walk,docs,publish}.spec.luau,experiments/prototype.patch,design-refute-007.md}`; `design-review-007.md`. Checks made, every run through `./zn run`:
- `experiments/prototype.patch` (unchanged since round 7) applied to a `git archive 1b78199b0` copy in `.cache/c0458-r8-proto`, its own repository, with the four specs copied into its `z-nile/tests/acceptance/c0458r8`. The copy's two commits took their identity from the environment (`@example.invalid`), no identity was written to any git configuration, and the copy is removed.
- On that copy walk passes 5/5, publish 4/4 and caps-modes 4/4. docs fails 2/2 at `docs.spec:22` and `:62`, because the copy holds today's skills.
- Six mutants of the prototype's `easy.raisedBy` against `walk.spec`, one at a time, each restored and the copy checked clean before the next. All six are red (lines under "Round 7 answers"). A clean run after the last is 5/5.
- Two spot mutants on the other formatted specs: `r.level` ignored by `work.activityOf` is red at `caps-modes.spec:119` (the case the rename touched), and `raiseWhole` disabled is red at `publish.spec:171`.
- `stylua --check z-nile/.tracker/issues/c0458` and `selene --quiet` on the same folder, from the worktree's root: both exit 0 (selene: 0 errors, 0 warnings).
- `./zn promote-check c0458` inside the copy, with the current specs: five type errors, none in c0458's four specs (`workread.luau` 1, `tests/tooling/easy-path.spec` 1, `tests/tooling/light-publish.spec` 3, all files the executor edits).
- `./zn capture c0458` compared with the document: Problem, Non-goals and Solution are the capture's text (the diff of the three sections is empty). The capture carries no marker.
- `./zn lessons --check`, `--uncovered c0458` and `--unattributed c0458` pass. The harvest lines for review 007 carry its step lines.
- origin/main is now 3f7dd44f6. Since the base it changed tracker files, `z-nile/next` and eight lesson files, none of which the four specs load. Two designs became prepared there after round 1, and neither changes this one: c0460 depends on c0458 and plans around `work.CODE_CHECKS`, and c0462's runner rule (a case with no assertion fails) is met by every case of the four specs.

Round 7 answers. The refute file disputes nothing, so there is no refutation to accept or re-raise.
- F1 is fixed.
  - The mirror line is at `walk.spec:277-278` (`Level: c0010 normal` then `Level: c0010 risky` gives risky) and passes on the prototype.
  - "The first line wins" (round 7's mutant, `out[ticket] == nil`) is red at `:278`. "The last line wins" is red at `:276`, and "the lowest line wins" is red at `:276`.
  - The row reads "the highest line wins per ticket, in either order", with both mutants and `run: AC8 red for both`. It agrees with item 10.
- F2 is fixed in its three parts, with one record left inexact (F1 below).
  - The run line's green half names `publish` and says "AC1, AC2 and AC4 pass".
  - E5 holds the three AC8 mutants. Its line numbers do not match what the runs give.
  - The duplicate "a line below" row is gone. The one that stays has its own mutant ("any line of normal or risky raises a short-noted ticket", red at `:273`), and the own-level row keeps both of its mutants (red at `:268` and `:270`).
- F3 is fixed. Both commands are clean on the folder, the parameter at `caps-modes.spec:104` is `risk`, the specs pass on the prototype as formatted, and the mutants above ran on the formatted files.

### F1 [low] E5's line numbers for the three new mutants are loose for two and missing for the third
Where: Unknowns & experiments, E5 ("in walk AC8 on the formatted specs: ..."); refute-007 F2
Evidence:
- E5 says "any line of normal or risky raising a short-noted ticket (`walk.spec` lines 273-274), the last line winning (line 275-277) and the first line winning (the mirror order) each turn it red".
- Run on the prototype with the formatted spec: the first mutant is red at `:273` only (`:274` passes `none`, so that mutant does not reach it), the second at `:276` (its statement is `:275-276`; `:277` starts the mirror statement), and the third at `:278` (its statement is `:277-278`).
- refute-007 F2 says E5 records the three "with their line numbers taken after formatting". The third has none.
Critique: the outcome of each run is recorded and is right, so nothing here lets a wrong implementation pass. The numbers are what an executor who rebases the prototype compares a rerun against, and a range that covers a line of another rule points at the wrong statement. This is the fourth refute in a row with a claim the document holds only in part (review-005 F4, review-006 F2 and review-007 F2 found the others).
Consequences: none. The numbers are a record, and no rule or spec reads them.
Recommendation: in E5 write the three as `walk.spec:273`, `:276` and `:278` (the lines the runner reports).
Lesson: z-design/restated-rules-move-together
Erred: z-design
Upstream: none

### F2 [low] The harvest drops round 7's lesson candidate as a one-off, on a reason the lesson it cites does not hold
Where: `harvest.md`, the line for `design-review-007 F1`; review-007 F1, Critique ("Lesson candidate for zz-review")
Evidence:
- The line says "one-off: ... the lesson z-design/spec-design-correspondence already asks for the mirror mutant".
- That lesson's `check:` asks whether a case's own mutant is killed by that case. Neither it nor its notes ask for a rule that picks one of several to be pinned in both orders: `grep -c -i "mirror\|both orders\|either order" z-nile/skills/z-design/lessons/spec-design-correspondence.md` prints 0.
- The finding is `Erred: zz-review`, `Upstream: none`. The lesson the reason leans on is under z-design, which is not in the finding's step group, so the designer's lessons pass shows it and a reviewer writing a Recommendation does not see it.
- This is the third finding in this item that is a reviewer's Recommendation taken as given, and all three are one-offs: review-003 F1 (high), review-005 F3 (medium) and review-007 F1 (medium). The last was round 7's only finding above low, so it alone is why this round ran.
- A lesson that fits exists: `zz-review/run-the-evidence-you-cite` already has the note "A Recommendation that lists cases is evidence too: check each listed case against what the real producer emits before prescribing it" (f0109 design review 003 F1). A design round's harvest has named it before (`z-nile/.tracker/rafts/R0093/harvest.md:36`).
Critique: a reviewer cannot write a lesson, so it gives the candidate to the lead, who adds a note to a lesson that fits or writes a new one (zz-review, Lessons). Here the candidate was closed with a pointer to a lesson that does not ask its question. The tempting fix is to reword the one-off's reason.
Consequences: a lesson under `zz-review` for the reviewer's own mistake is exempt from the `when: design` rule (z-design step 5), so `build` on that lesson is allowed on this line. The lesson file changes, so `./zn lessons --check` is rerun.
Recommendation:
- Add a note to `zz-review/run-the-evidence-you-cite` with this source (c0458 design review 007 F1): a Recommendation that gives spec lines for a rule that picks one of several (highest, first, last) gives the lines in both orders, and each was run against the mirror mutant.
- Change the harvest line to `- design-review-007 F1 (erred zz-review): zz-review/run-the-evidence-you-cite`, and run `./zn lessons --check`.
Erred: z-design
Upstream: none

Verdict: approve
