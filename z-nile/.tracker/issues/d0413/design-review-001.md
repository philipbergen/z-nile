# Review 001: d0413 (design mode)
Inputs: a6df15490 (prep-loop-scan-red-on-main): d0413.md, guesses.md, check.sh, acceptance/loops.spec.luau, prototype.patch, experiments/E2-mutants.sh, experiments/E2-results.txt, idea-review-001.md, idea-refute-001.md; `./zn capture d0413` (a746f7efe); runs in `.worktree/scratch-main-full` (prototype applied, adf9ace13) and in this worktree (origin/main's engine): the acceptance spec 5 passed in 1.5 s; `meta/scanning-loops`, `c0193/tree`, `c0116/plan`, `f0399/plan`, `f0399/guesses`, `tooling/raft-plan-deps` and `c0136/renumber-streams` all pass on the prototype; the 12 slow-tier specs of the affected list give `92 passed, 4 failed` on both trees, the same four cases (F3).

### F1 [medium] The promoted AC1 case pins the current set of reviewed loops in two files, so a later legitimate edit to either file turns d0413's promoted spec red
Where: acceptance/loops.spec.luau, case "the loop scan finds no unproven loop in guesses.luau or raftplan.luau, and no new listed loop"; d0413.md Regression guard ("New and permanent once promoted: the order, ring, self-dependency and trailing-line cases")
Evidence: the case asserts `loops.ALLOWED["z-nile/engine/guesses.luau"] == nil`, `#loops.ALLOWED["z-nile/engine/raftplan.luau"] == 1` and `listed[1].loop == "while parent[k] ~= k do"`. `./zn done` promotes the whole file to `z-nile/tests/acceptance/d0413/`, not only the cases the Regression guard calls permanent. A later issue that adds a reviewed, text-reading loop to `guesses.luau` (zz-arch rule 9 allows a listed loop with its sweep), or rewrites the union-find in `raftplan.plan` (`find`'s `while`, line 297 with the prototype), goes red on d0413's promoted spec. That is an Override the later issue's author will not foresee, since its `affected` output lists the spec only by its requires, not by what the case means.
Critique: "the reviewed list gains no entry" is a fact about this delivery, not a rule of the tooling: the rule ("every loop is proven or listed with a reason") is already pinned for every file by `meta/scanning-loops` and `c0193/tree`. The tempting fix is to delete the three `ALLOWED` assertions, which leaves "gains no entry" (a captured Solution line) without any check, so an executor could list the two `while` loops instead of rewriting them and pass AC1 and AC5.
Consequences: a check.sh-only check must not compare with a fixed sha (it goes stale when main moves); comparing with the merge base passes vacuously after landing, which is acceptable only because the check has already bound at `finish` and `done`.
Recommendation: split AC1. The spec case keeps only the rule: `loops.problems(path, files[path], loops.ALLOWED[path], scanners.files())` is empty for both files. "The list gains no entry" moves to check.sh, outside the promoted spec: `check "AC1b: …" git diff --quiet "$(git merge-base origin/main HEAD)" HEAD -- tests/lib/loops.luau` (run from z-nile's home, where `ac.sh` puts it). Record a mutant for it ("the two `while` loops listed in `loops.ALLOWED` instead of rewritten") and run it red. Update the Rules table (the M9 row now names both checks), the Test plan and E2's record.
Lesson: zz-test/promoted-specs-pin-rules-not-sets
Erred: zz-test
Upstream: z-design

### F2 [medium] The Root cause cites a lesson that does not exist as the only cover for the gap it leaves open
Where: d0413.md, Design, Root cause ("the lesson `zz-execute/run-the-loop-scan-after-adding-a-loop` covers the gap for the executor")
Evidence: no file `run-the-loop-scan-after-adding-a-loop.md` is under any `z-nile/skills/*/lessons/`. `git log --all -S run-the-loop-scan-after-adding-a-loop` finds only this prep's draft commit, which mentions it only in d0413.md. The folder has no `harvest.md` that adds it. The Non-goal keeps the watch-map gap open (the scan specs are not selected when an engine file gains a loop), and this sentence is the design's only answer to "how does the next raft avoid this".
Critique: the defect happened because the executor of f0399 had no prompt to run the loop scan. If the design asserts a safeguard that is not there, the next loop-adding raft repeats it, and a reader of the design believes it was handled. The tempting fix is to delete the sentence, which leaves the cause of the red main with nothing to prevent it again.
Consequences: a lesson the lead writes must sit under the step that erred, with a harvest line, and must be a rule another raft could fail. The existing `zz-test/specs-read-sources-through-the-selector` already asks the selector question for a spec that reads sources as text, so a second near-duplicate lesson would split the rule.
Recommendation: as the lead of this prep, add a note to the existing lesson `zz-test/specs-read-sources-through-the-selector`, or write the zz-execute lesson if the rule is "after adding or changing a loop in the tooling, run `tests/meta/scanning-loops.spec.luau` by path before `finish`". Make its `when:` fit its step and record it in d0413's `harvest.md` as a `- note … (erred zz-execute[, upstream …]): <lesson id>` entry. Then make the Root cause sentence name the file that exists. Do not make it a ticket.
Erred: z-design
Upstream: none

### F3 [low] The regression record leaves out the slow tier, which holds half of the affected specs for the two engine files
Where: d0413.md, Regression guard ("the affected gate runs them"), E4, Affected specs
Evidence: of the 24 specs `lune run z-nile/affected` lists for `guesses.luau` and `raftplan.luau`, 12 are in `z-nile/tests/slow.tsv` (`c0116/claims`, `compact-record`, `issue-design`, `plan-cli`, `plan`, `recombine`, `retired`; `tooling/approve-publish`, `approve`, `recombine-members`, `stack-land`, `work`). Neither `--affected` nor `--full` runs them, and E4 runs only fast specs. `c0136/renumber-streams.spec.luau` requires `@znile/engine/raftplan` but is in neither the affected list nor E4. I ran the 12 slow specs by name on the prototype and on origin/main's engine: both give `92 passed, 4 failed`, with the same four cases (`c0116/claims` "a redesign landed after the carried move…", `c0116/compact-record` ×2, `c0116/retired` "on a clone holding a retired raft…"), which are main's known slow reds. `c0136/renumber-streams` gives 5 passed on the prototype. So nothing regresses, but the design's record does not show it.
Critique: the Overrides line "none" rests on a suite that skips the specs that drive `raft-plan`, `recombine` and `approve` end to end.
Consequences: none beyond the record. check.sh must not run slow specs (zz-test/check-sh-never-runs-the-slow-tier).
Recommendation: add the slow-tier comparison above to E4, and name the 12 slow specs in the Regression guard as slow tier, run by name once in an Implementation step and not in check.sh. A red that origin/main does not show is a stop and an Override, not this issue's to absorb.
Lesson: z-design/confirm-overrides-with-a-suite-run
Erred: z-design
Upstream: none

### F4 [low] AC4's case matches a prefix, so "every entry exactly once" is not pinned exactly
Where: acceptance/loops.spec.luau, case "a list that repeats an id is planned, every entry once, instead of never returning"
Evidence: `string.find(r.stdout, "planned f0010,f0010,f0011", 1, true)` also accepts `planned f0010,f0010,f0011,f0011` and `planned f0010,f0010,f0011 | f0011`. A planner that ends but adds an entry twice (for example a fallback that re-picks an entry already taken by id, after an extra pass) passes AC4.
Critique: the captured Solution says "its result holds every entry of the list exactly once". The case checks that the expected entries are there, not that nothing else is.
Consequences: none. The driver prints exactly one `planned …` line.
Recommendation: match the whole line, for example `string.match(r.stdout, "planned ([^\n]*)") == "f0010,f0010,f0011"`, and add the mutant "an entry already taken is appended again" to the Rules table, run red.
Erred: zz-test
Upstream: z-design

### F5 [low] The Design states a rule for repeated ids that no case pins and the capture does not ask for
Where: d0413.md, The change, item 2 ("an id counts as met once any entry carrying it is taken"); Rules and mutants
Evidence: the only repeated-id case is `{f0010, f0010, f0011→f0010}`. For that input, "met once any copy is taken" and "met once every copy is taken" give the same order. Take the list `{f0010→f0012, f0010, f0011→f0010, f0012}` (sorted). The Design's rule takes `f0010` (the second copy), then `f0011`, before the first `f0010`, which is placed after the issue that depends on it. Nothing in the Rules table names this rule, and no case can tell the two readings apart.
Critique: either it is a promise (then it needs a row and a case), or the order among repeated ids is unspecified (the capture promises only that the planner ends and holds each entry once).
Consequences: pinning it fixes, for a list the Non-goals call malformed, a behaviour that a later fix to reject repeated ids would have to override.
Recommendation: say in the Design that for a repeated id only termination and "every entry once" are promised and the order is unspecified, and leave the Rules table as it is. Do not pin the order.
Erred: z-design
Upstream: none

### F6 [low] Implementation step 3 gives no rule for a red that is not this issue's, and runs every project's gate when the outcome names z-nile's stage
Where: d0413.md, Implementation steps, step 3; AC5's G1
Evidence: step 3 says "its z-nile stage has no failure". Main moves between prep and execution, and any other merge's red (like the slow-tier reds above, had any been in the fast tier) leaves the executor unable to meet the step, with no instruction. `z-nile/check.sh --full` with no `--project` also runs pickman, arcade, portal, snake, invaders and asteroids (pickman's 313 spec files in E1), which the captured outcome does not ask for.
Critique: an executor either stops on a red that is not theirs or "fixes" it in this issue.
Consequences: a red that origin/main also shows must be recorded and named, never absorbed. A red only on the branch is a stop.
Recommendation: step 3 runs `z-nile/check.sh --project z-nile --full`. Any failing spec is run by path on origin/main: one that fails there too is recorded in the Verification log as main's red (zz-execute Phase 6's wording) and does not block, and one that fails only on the branch is a stop.
Erred: z-design
Upstream: none

Verdict: changes
