# Review 003: c0192 (design mode)
Inputs: worktree `prep-lesson-bound-every-probe` at a6aabd18 plus the uncommitted `c0192.md`, `check.sh`, `harvest.md`, `design-refute-001.md`, `design-refute-002.md` and `experiments/`. Other items:
- c0191 at `origin/prep-no-leaked-processes` 130dacc1. Since round 2's 88168bf6 only its `spend.md` changed (`git diff --stat 88168bf6 130dacc1 -- z-nile/.tracker/issues/c0191`).
- c0181 at `origin/prep-lessons-codify-consolidate` 70fa9f21.
- c0136 and c0193 at `origin/main`.
- c0166 at `origin/prep-relevant-review-lessons`.
- c0165 in the worktree `prep-reuse-test-results` (`design: reviewed`).
- c0180 in `prep-hybrid-inprocess-gate` (`design: reviewed`).
- `./zn capture c0192`; `./zn lessons --skill zz-review --full`; `--when design --full`.

Dropped from design-review-002: F1, F2 (each fix re-run below).

Re-run evidence:
- **Real worktree.** `./zn check c0192`: 0 of 5, each for the right reason (no lesson; "AGENTS.md carries no bounded-command rule (c0191 not landed?)"; no Enforced by line; "not listed for --when design"; "no meta spec").
- **Clone setup.** A throwaway clone of a6aabd18 under the scratchpad, deleted afterwards, with c0136's `experiments/prototype.patch` applied to the engine (`git apply --include='z-nile/engine/*'`) and this round's item folder copied in.
- **Round 2 F1, the c0136-first grouping and its mutant row.**
  - Ungrouped harvest: `./zn lessons --unattributed c0192` lists `c0192 design-review-001 F1` to `F6` and `design-review-002 F1`, `F2`, and exits 1 (the mutant dies).
  - Grouped the way Design 8 and step 4 say (`- design-review-00N F<n> (erred z-design): …`), with `ref-lesson.md.txt` in place and the note `… (PR #125) (erred zz-review): zz-review/bound-every-probe` appended: `harvest: every entry names its step` (exit 0), `lessons: 163 lessons, 1160 harvest entries, ok`, and `harvest: every finding is covered`. The note's own `(PR #125)` stays text, as c0136's pattern `^(.-)%s*%((erred [^()]*)%)$` says.
- **Round 2 F2, the stale text.** No Behaviour change, Existing work, Scalability, Design 6 (c0180 moves the `reap` command, not the pure file) and the Regression guard's type pass are corrected. A search for the old words (`no test`, `no new rule`, `13-line`, `engine/cmd`, `lune's type`) finds none left.
- **Facts re-checked.**
  - The rule sentence in both reference lessons equals c0191's `docs.spec` `RULE` (`grep -cF` gives 1 each).
  - Both reference lessons have a body of 1,153 bytes; they are 13 and 15 lines.
  - c0181 hides only **fully** enforced lessons under `--when` (its `select`: "a fully enforced lesson is left out when `when` is set"). The c0181-first lesson (`enforced: part`) therefore still meets AC4's `--when` listing.
  - Under c0166 the lesson carries the core tags `process` and `review`, so `--for … --mode …` keeps it in every mode.

### F1 [medium] "The meta case runs in every gate" holds only for full gates: an `--affected` run never runs it for an AGENTS.md edit today, and under c0165 the undeclared reads let it be reused after one
Where: Design 6 ("the meta case runs in every gate, so a later edit of the sentence in `AGENTS.md` … turns the gate red"); Restated rules; Maintainability; Chore checklist, Existing work (c0165 is not listed); Implementation steps (none adds an `inputs.tsv` line).
Evidence:
- **Today.** `lune run z-nile/affected -- AGENTS.md` prints nothing (exit 0). AGENTS.md is in no home, so `affected.luau`'s `SHARED_FULL`, `HOME_FULL` and `TOOLING` rules all miss it. An `--affected` gate on a change that edits only AGENTS.md's sentence runs no spec, and the meta case is not among them.
- **c0165** (`design: reviewed`, no order against c0192) makes affected runs reuse each spec's last pass by a fingerprint of its require closure plus the inputs it declares. Even `ALL` stands for "every spec file", each reused when its fingerprint is unchanged. Its zz-test wording reads: "**Declared inputs**: a spec that reads files or git state outside its requires declares them in its home's `tests/inputs.tsv`". Its New specs bullet says "Review checks it, and the full gate learns what it missed".
- **What the meta case reads.** Outside its requires (`boundcmd`), it reads `AGENTS.md` and `z-nile/skills/zz-review/lessons/bound-every-probe.md` as text, and it tests six paths with `fs.isFile`. With c0165 landed and no declaration, an edit to the lesson or to AGENTS.md keeps the case's fingerprint, and every affected run reuses its old pass.
- **The other order.** c0165's own lists are "copied exactly from this issue's `declared/pickman.tsv` … and `declared/z-nile.tsv`", from an audit of the 401 specs that existed on 2026-10-27. If c0192 lands first, c0165 ships without the meta spec's lines.
- c0191 says "this issue's new specs get their lines when those land, by their own mechanism". c0192 copied c0191's shape but says nothing about c0165.

Critique: the drift is still caught by the full gate at the merge (`land`, `done` and CI run every spec fresh under c0165), so no wrong lesson reaches main. The failure is that the guard round 1 F2 asked for fires late, and in the c0165-first order the new spec breaks a zz-test rule that its code reviewer must raise. The tempting fix is to change "every gate" to "every full gate" and stop there. That leaves c0165's rule broken in one order, and its list incomplete in the other.

Consequences:
- An `inputs.tsv` line exists only once c0165 has landed. `check.sh` can't require it in both orders, so the step goes in the Implementation steps and the code review, not in an AC.
- c0165 accepts a path under a project root only below the root. None of these paths is under a tracker root.
- The inputs to declare are the lesson, AGENTS.md and the six enforcer paths. Those paths already force z-nile's full run or sit in the require graph, except AGENTS.md and the promoted `docs.spec.luau`.
- If c0192 lands first, c0165's `declared/z-nile.tsv` and its AC13 list need the lines. That is c0165's sequestered file, which its own lead edits.

Recommendation:
- Add an Implementation step: if `z-nile/tests/inputs.tsv` exists (c0165 landed), add `tests/meta/bound-every-probe.spec.luau` lines for `AGENTS.md`, `z-nile/skills/zz-review/lessons/bound-every-probe.md` and `z-nile/tests/acceptance/c0191/docs.spec.luau`, plus the other enforcer paths if c0165's rule asks for every read.
- Otherwise, report the lines to c0165's lead for its `declared/z-nile.tsv`, the way Design 7 reports c0181's row.
- Add c0165 to Existing work with both orders.
- Reword Design 6, Restated rules and Maintainability to say what runs when: every full gate (land, done, CI), and an affected run once the reads are declared.
- Add a `reasoned` row to Rules and mutants: "the meta case is selected when AGENTS.md changes | c0165's selector | the line missing from `inputs.tsv`".

Lesson: z-design/quote-other-preps-before-promising

### F2 [medium] A meta case with no assertions passes AC5, so the outlive-`done` pins of round 1 F2 rest on nothing sequestered, and Design 6's "twins keep the executor from weakening the case" is false
Where: Design 6 ("AC2, AC3 and AC5 are the sequestered twins that keep the executor from weakening the case"); check.sh AC5; Rules and mutants (the meta-case rows are marked `run` in prep, and nothing re-runs them on the executor's file); Design 7 (`- codify … mutant: boundcmd lets a bare lune run through`).
Evidence: in the clone (no c0181), I wrote `z-nile/tests/meta/bound-every-probe.spec.luau` as one empty case:
```
it("[zz-review/bound-every-probe] a bare probe is refused and the wrapped one passes, and the lesson carries the AGENTS.md rule and names files that exist", function() end)
```
AC5's steps then go: the file exists; `grep -qF "[zz-review/bound-every-probe]"` passes; the `enforced_by` branch is off; `lune run tests/run -- <spec>` gives `1 passed, 0 failed, 1 spec files`, exit 0.

AC2 and AC3 read the lesson, not the case, so they say nothing about it. The meta case's five assertions (refused bare probe, the `say` names the wrapper, the wrapped probe passes, AGENTS.md's sentence is in the lesson, every named path exists and there are at least five) are Design 5's only. After `done` they are the only guard of round 1 F2's drift, and no `check.sh` line kills a mutant of them. The prep's `run` rows proved the reference text (`ref-meta-spec.luau.txt`), not the file the executor writes, which "adapts to c0191's landed `boundcmd`" (step 2).
Critique: a wrong implementation (a vacuous or partial case) passes every Checked criterion. Only the code reviewer's reading stands between it and `done`. In the c0181-first order the `- codify` line then records a `mutant:` that nobody ran on that file. The tempting fixes are a Judged criterion, which is wrong because mutating the inputs is measurable, not subjective (zz-test: "If something could be expressed as a measurable proxy, it's not Judged"), or deleting the claim from Design 6.
Consequences:
- A real mutation check can't edit AGENTS.md or the lesson in the checkout. It needs a fixture. The case reads `git rev-parse --show-toplevel`, so a fixture must be a whole-tree clone (`@tests/lib/clone`, `--no-hardlinks`, under `.cache/<unique>`), costing one clone per `./zn check`.
- A text proxy is cheap but beaten by a deliberately hard-coded case. The code reviewer covers that (zz-review code item 3, "would pass with a stub").
- Either way the check pins only call shapes this issue owns (`boundcmd.check(`), not c0191's internals (z-design/late-pins-run-on-the-merged-deps-tree).

Recommendation:
- At least, extend AC5 with a text proxy that the case does each of Design 5's jobs:
  - the spec holds `boundcmd.check(`, `"./zn run --time`, `"AGENTS.md"`, `bound-every-probe.md`, `isFile` and `when you do.`;
  - a mutant row "the case's body emptied (AC5 fails)" is run on the reference text.
- Better, if the cost is acceptable: AC5 runs the executor's spec in a `.cache` clone fixture three times, with AGENTS.md's sentence edited, the lesson's sentence edited and `z-nile/engine/reap.luau` removed, and each run must fail.
- Either way, reword Design 6 to say which twin holds what. Add a step for the executor: before the `- codify` line, run the mutant it names on the file it wrote.

Lesson: zz-test/no-vacuous-pass

### F3 [low] c0191 and c0181 both create `z-nile/lib/bounded.pl` with different contracts; the lesson names that path as "the runner" and teaches c0191's exit codes, and no prep has said so
Where: Design 4 and the lesson's **Enforced by** (`z-nile/lib/bounded.pl` (the runner)); How to apply (`124 (wall clock)`, `125 (CPU)`); Chore checklist, Existing work (c0181 is listed only for its lesson format); U1.
Evidence:
- c0191 (`design: ready`) has a Design section headed `` ### `z-nile/lib/bounded.pl` (new; reference: `experiments/ref-bounded.pl.txt`) `` and lists the path in its Touched modules. Its interface is `--time`/`--cpu`, exiting 124 or 125.
- c0181 (`design: ready`) builds the same file in W0. Its prove step runs "under a time limit (`--limit <seconds>`, default 600, a new `z-nile/lib/bounded.pl` that runs the command in its own process group and kills the group when the limit passes, or when its stdin … reaches end of file … and refuses a group id of 1 or less"). It touches `z-nile/lib`.
- `grep c0181` over c0191's document and `grep c0191` over c0181's document find nothing.
Critique: c0192 depends on c0191 and checks only that the file exists, so its checks pass in either order. But the lesson teaches one contract for a path two issues define, and the second of them to land must merge the two. The Existing work survey (round 1's quote-other-preps fix) read c0181 for its lesson rules only.
Recommendation: add the collision to Existing work. Say that c0192's lesson follows whatever contract c0191's acceptance `bounded.spec` pins at c0191's `done`; step 1 already re-reads the landed names. Report the collision to the c0191 and c0181 leads, as Design 7 does for c0181's row. c0192 needs no design change.
Lesson: z-design/quote-other-preps-before-promising

Verdict: changes
