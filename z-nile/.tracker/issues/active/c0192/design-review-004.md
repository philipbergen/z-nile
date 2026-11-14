# Review 004: c0192 (design mode)
Inputs: worktree `prep-lesson-bound-every-probe` at a6aabd18 plus the uncommitted `c0192.md`, `check.sh`, `harvest.md`, the design rounds 001 to 003 and their refutes, and `experiments/`. Other items:
- c0191: its prep has landed on `origin/main` (a1272ede, PR #203), `design: ready`. `git diff --stat 130dacc1 origin/main -- z-nile/.tracker/issues/c0191` is empty, so its document is the one round 3 read.
- c0181 at `origin/prep-lessons-codify-consolidate` 9d94f287 (a merge of main). In its folder only `spend.md` changed since 70fa9f21.
- c0165 in the worktree `prep-reuse-test-results` (65ffdc02, `design: reviewed`).
- c0180 in `prep-hybrid-inprocess-gate` (19b088e0, `design: reviewed`).
- c0136 and c0193 at `origin/main` 7373e78c.
- `./zn capture c0192`; `./zn lessons --skill zz-review --full`; `--when design`.

Dropped from design-review-003: F1, F2, F3 (each fix re-run below).

Re-run evidence:
- **Real worktree.** `./zn check c0192` passes 0 of 5, each for the right reason: no lesson; "AGENTS.md carries no bounded-command rule (c0191 not landed?)"; no Enforced by line; "not listed for --when design" (after `lessons: 162 lessons, … ok`); "no meta spec".
- **Round 3 F2, AC5's text proxy.** I ran check.sh's own loop over two files in the scratchpad.
  - Over `ref-meta-spec.luau.txt`: the case name is found and all six words are present.
  - Over an emptied case that carries the **designed** name (`it("[zz-review/bound-every-probe] a bare probe is refused … the lesson carries the AGENTS.md rule and names files that exist", function() end)`): four words are missing (`boundcmd.check(`, `zn run --time`, `isFile`, `when you do.`). AC5 fails, so the mutant row holds. See F1 for the two words that were not missing.
  - `tests/acceptance/c0120/check-paths.spec` on the extended `check.sh`: 4 passed.
- **Round 3 F1, Design 6 and step 6.**
  - `lune run z-nile/affected -- AGENTS.md` prints nothing (exit 0).
  - The lesson and harvest paths print `ALL`.
  - zz-test's table runs `--full` in `land`, and c0165's gate table has `./zn done` run `z-nile/check.sh --full` fresh. So "every full gate" holds today.
  - c0165's format line reads "`<home-relative spec path>\t<input>`, where input is a repo-relative file …". Its root rule allows "A path under a project root … only below it". Step 6's six lines match both, and none of the paths lies under a tracker root.
- **Round 3 F3, the bounded.pl collision.** c0181 at 9d94f287 still builds "a new `z-nile/lib/bounded.pl`" with `--limit <seconds>`, default 600, which kills the group on stdin EOF. c0191 still has `### \`z-nile/lib/bounded.pl\``, exits 124 and 125, and "c0193 and the lesson c0192 run `./zn run --time N -- <cmd>`". The Existing work text is accurate, except for one word: see F3.
- **Facts re-checked.**
  - The ref lesson's rule line equals c0191's `docs.spec` `RULE` (`grep -cF` gives 1).
  - `boundcmd.check(command: string, ctx: Context?): Verdict` with `say: string?`, from c0191's `ref-boundcmd.luau.txt`.
  - c0181's spec ref accepts `it(` followed by whitespace and the quoted name (stylua's wrapped form, which the reference uses).
  - c0136's rule 2 needs design-review-003 F2's entry (`zz-test/no-vacuous-pass`) grouped with `upstream zz-test`. Step 4's "each lesson filed under the group's skills" covers it.
  - No worktree or main item other than c0191, c0193 and c0181 names `zz-review/lessons/` or `bound-every-probe` (only a review file in `capture-sweeper-kill-c0132`).
  - The prep added no lesson files this round, so there is no harvest to judge.
  - Scope: the captured Problem is unchanged; every outcome has a Design and AC1 to AC5.

### F1 [low] Two of AC5's six proxy words are satisfied by the case's own required name, and E8's "five of the six" was measured on a shortened name
Where: check.sh AC5 (`"AGENTS"`, `"bound-every-probe"`); Design 6; E8.
Evidence: Design 5 and 7 require the case name `[zz-review/bound-every-probe] … the lesson carries the AGENTS.md rule …`, and in the c0181-first order the `enforced_by` ref quotes it whole. That name alone contains `AGENTS` and `bound-every-probe`. With the designed name, an emptied case misses four words, not the five E8 records. E8 used `it("[zz-review/bound-every-probe] …", …)`, a name with an ellipsis. So the label's jobs "AGENTS.md" and "the lesson" are never shown by the proxy. A case that keeps `boundcmd.check(`, `isFile` and the `when you do.` text but drops the read of `AGENTS.md` or of the lesson passes AC5. Round 3 recommended `"AGENTS.md"` and `bound-every-probe.md`; the refute shortened both.
Critique: the emptied-case mutant still dies, so round 3 F2's point is fixed. What is left is a proxy with two dead words and a wrong count in E8. Design 6 already gives a hard-coded case to the code reviewer, so this is clarity, not a hole the executor would fall into.
Consequences: pinning the quoted spelling `"AGENTS.md"` makes the executor write that exact literal (zz-test/source-pins-name-what-the-design-names), so the Design has to name it.
Recommendation:
- Use `"AGENTS.md"` (with the double quote) and `bound-every-probe.md`. Neither occurs in the designed name; both occur in the reference (`read("AGENTS.md")`, `LESSON`).
- Name those two spellings in Design 5 or 6.
- Re-run E8 with the full designed name and record the count.

### F2 [low] The order of the mutant runs disagrees with Design 6 and with the steps: Design 6 points at "step 2", and step 4 writes the `- codify` line before step 5 runs its mutant
Where: Design 6 ("the executor's own mutant runs on the file it wrote (step 2, … before any `- codify` line records them)"); Implementation steps 3 to 5.
Evidence:
- The mutant runs are step 5, not step 2.
- Step 4 appends the `- codify` line (c0181-first), and step 3 makes steps 2 to 4 one commit. Step 5 then clones that commit, so the clone needs the committed files, and runs "boundcmd lets a bare lune run through". The line therefore records a mutant before anyone has run it, which is the reverse of what Design 6 and design-refute-003 say.
- Step 5's bare `lune run tests/run` inside a `mktemp -d` clone is refused by c0191's hook. Its TOOLING passes a relative target "only when the call's `cwd` … is inside" the checkout: "a scratch copy of the tooling is a probe like any other". Only step 7's general sentence says to wrap it.
Critique: an executor who follows the steps in order writes the codify line first. If the mutant then survives, the line is already committed.
Consequences: moving the codify line into a later commit risks a red gate between commits in the c0181-first order, where c0181's policy wants the line for an `enforced_by` lesson (z-design/no-check-red-between-steps).
Recommendation:
- Run step 5 before the commit. Clone HEAD, copy the uncommitted spec and lesson into the clone, and run the mutants as `./zn run --time 120 -- lune run tests/run -- tests/meta/bound-every-probe.spec.luau` from the clone's `z-nile/`.
- Only then append the `- codify` line and make the one commit of steps 2 to 5.
- Fix Design 6's step number.

### F3 [low] The stale-words sweep missed "every gate" and two small facts
Where: Non-goals (line 24, "enforcing ref in every gate"); Solution (line 29, "holds in every gate"); Design 5 (line 39, "so every gate runs it"); Restated rules (line 55, "the meta case (in every gate)"); Scalability (line 60); AC5 (line 137, "run in every gate"); check.sh AC5's label; the reference lessons' Enforced by line (`(in every gate)`); Design 6's list; Existing work.
Evidence:
- `grep -n "every gate"` finds these places, while Design 6 now says "every full gate", and "in an `--affected` run only when that run selects it".
- Design 6 lists the full gates as "`land`, `done`, CI". The user's decision of 2026-10-31, recorded in c0180 lines 28 to 31 and being folded into c0165, makes `done` affected ("So `done` no longer runs the full gate"). It puts the one full gate at zz-rules Merging step 2, which the list omits.
- Existing work says of c0191 and c0181 that "neither document mentions the other". Each names the other (c0181 line 150, c0191 line 150), just not about `bounded.pl`.
- The Checked AC5 and Test plan AC5 omit the text proxy that check.sh's AC5 label states.
Critique: none of this changes what the executor builds or what passes. A lesson that tells agents its case runs "in every gate" repeats the claim round 3 F1 corrected.
Consequences: none.
Recommendation:
- Reword those places to "the gate", or "every full gate" where timing matters, including the reference lessons' `(in every gate)` and the check.sh label.
- Write Design 6's list as "every full gate (`land`, the merge gate, CI; today also `done`)".
- Say "neither mentions the other's `bounded.pl`".
- Add the proxy to the Checked AC5 and the Test plan line.
Lesson: z-design/restated-rules-move-together

Verdict: approve
