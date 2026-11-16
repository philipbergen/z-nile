# Review 001: R0072 (code mode)
Inputs: layer 2 (c0193), `git diff origin/R0072/1/c0192...HEAD` at 92112d9c (= origin/R0072/2/c0193; origin/main 4fda0d2c after `./zn sync --fetch`); `z-nile/.tracker/issues/active/c0193/c0193.md`, its `check.sh` and `acceptance/`; `z-nile/.tracker/rafts/active/R0072/R0072.md`.

What I ran:
- `./zn check c0193`: 9/9 pass. `./zn promote-check c0193`: `promote-check OK`. `lune run z-nile/watch-check`: clean.
- `z-nile/check.sh --affected`: static stages clean; 213 passed, 3 failed, all three in `tests/tooling/wrapper-guards.spec.luau`. With `z-nile/bin` taken off `PATH` the same spec passes 4/4. Its fixture pushes `main` through the `git` on `PATH`, which in this dispatched session is the `z-nile/bin/git` wrapper. So the dispatch environment causes it, not this diff. `tests/tooling/repo-fence.spec.luau` (one case, :593) fails here for the same reason and passes 10/10 without the wrapper. This layer touches neither spec's inputs; the only overlap is `tests/inputs.tsv`, which just selects them.
- Sequestration (`git diff --find-renames=100% --name-status origin/main...HEAD -- 'tracker/**/check.sh' 'tracker/**/acceptance/**' '*/.tracker/**/check.sh' '*/.tracker/**/acceptance/**'`): one entry that is not R100, `A z-nile/.tracker/issues/active/c0193/acceptance/watch.txt`. `./zn finish` writes that file (`z-nile/engine/main.luau:3774` calls `watchcmd.capture` with `{issue.dir}/acceptance`; zz-test, Affected selection, Capture: "`./zn finish` is the only writer"). Its five paths are exactly this layer's changed source files, and no spec or `check.sh` changed. Not a finding (see the candidates at the end).
- Probes, all through `./zn run --time 60 --`, with scratch files under `z-nile/.cache/rev-r0072/` (removed):
  - `loops.find` over the shapes quoted below.
  - The real tree: 82 loops in 117 covered files, 5 proven (`z-nile/affected.luau:31`, `z-nile/engine/stats.luau:169`, `z-nile/record.luau:29`, `z-nile/specs.luau:109`, `z-nile/tests/run.luau:360`).
  - A copy of `loops.luau` that prints every loop whose end it cannot find: none in the tree.

### F1 [high] loops.find proves loops that spin: compound assignments and typed shadowing locals are not seen as writes
Where: z-nile/tests/lib/loops.luau:68-73 (`assigns`), used at :162
Evidence: `loops.find` on each text (probe output):
- `while i < n do / i += 1 / i *= 0 / end` gives advances=true
- `while i <= n do / i += 1 / i %= n / end` gives advances=true
- `while i < n do / i += 1 / i //= 2 / end` gives advances=true
- `while i < n do / local i: number = 0 / i += 1 / end` gives advances=true. The step moves the shadow, so the outer `i` never changes.

Each of these loops spins forever, yet the lint "proves" it, so it needs no entry and no reviewer ever reads it. (`local i = 0`, `i = 0` and `i ..= ""` are correctly refused.) The pattern `^%s*([%w_,%s%.]-)%s*[%+%-]?=[^=]` only admits `=`, `+=` and `-=`, after names with no `:` annotation. By the same reading, `/=` and `^=` slip through too, and so does a typed `for i: number =` in the body. AC4 says "nothing else in the body resets or steps back that variable". The sequestered `loops.spec` has no such case, so `check.sh` passes this wrong implementation.
Critique: The author will be tempted to add `*` and `/` to the operator class. That still misses `//=`, `%=` (which needs `%%`), `^=` and the typed declarations. A hand-picked operator list leaves the same hole for the next form.
Consequences: Widening "assigns" can only turn a proven loop into a listed one. That fails closed. It must not start counting comparisons (`==`, `~=`, `<=`, `>=`) or method calls, though: if it did, some of the 5 proven loops in the tree would become unlisted problems and the gate would go red. The Design's rule 3 defines an assignment as "ending in `=`, `+=` or `-=`", so the code would differ from the Design's wording (in the safe direction), and c0193.md must record that. The sequestered `loops.spec` cannot gain the cases.
Recommendation:
- In `assigns`, take the text before the line's first assignment operator: any of `=`, `+=`, `-=`, `*=`, `/=`, `//=`, `%=`, `^=`, `..=`. That is an `=` not preceded by `=`, `~`, `<` or `>` and not followed by `=`.
- Count the line as a write when V appears there as a whole word, including after `local`, `for` or `if … then`, and inside a type annotation (`local i: number`).
- Record the deviation from the wording of Design rule 3 in c0193.md, citing this finding.
- Add an executor-written spec outside `acceptance/` (for example `z-nile/tests/tooling/loops-writes.spec.luau`, its watch file written by `./zn finish`):
  - Cases that must not prove: a step followed by `*=`, `/=`, `//=`, `%=` or `^=` on V; a typed shadow `local i: number = 0` before the step; a typed `for i: number = 1, 2 do` in the body.
  - Cases that must still prove: `i += 1` alone; `i += 1` with `if i == n then` and `t:push(i)` in the body. These make the "never prove" and "count comparisons" mutants fail.
- Rerun the meta case. The 5 proven loops must stay proven; no loop in today's tree uses the new forms.

### F2 [high] The promoted finishes.spec starts two real spinners and waits for a real limit in every full gate
Where: z-nile/.tracker/issues/active/c0193/acceptance/finishes.spec.luau:192 ("fails a scanner that never returns…") and :211 ("names the witness when a scanner hangs on it…"). Both use the `SPINS` fixture (:15) with a 3 s limit. `./zn done` promotes them to `z-nile/tests/acceptance/c0193/`.
Evidence: Each case starts a `lune` child that loops at 100% CPU until `bounded.pl` kills it after 3 s of wall time. The affected run lists `finishes.spec.luau 13.0s` and `scanners.spec.luau 9.8s` as its slowest specs. The lesson zz-test/specs-never-burn-real-resources says a promoted spec never "spin[s] … or wait[s] for a real limit to fire", and quotes the user's ruling on c0191: "You can use it to prove that your implementation works and then it gets removed. I'm not running that." That lesson landed in c0191's re-prep (#221, 2026-11-01 22:06 PST), 13 hours after c0193's prep (#196, 09:21 PST). None of c0193's five design reviews could apply it, and nothing re-checked the specs when the raft was readied.
Critique: The executor cannot fix this, because the cases are sequestered (zz-execute stop conditions). If it stays, `done` puts into every full gate the exact thing the user refused.
Consequences: Re-prepping changes sequestered files, so that change needs its own design review. The suite must still kill the mutants on how a hang is reported (its block, its witness, the 124/125 wording) through a stand-in, or the Rules and mutants table loses rows.
Recommendation: escalate to the user, with these options:
- (a) Re-prep c0193's finishes.spec. The two hang cases become a proof script in `acceptance/` with no `.spec.luau` name, which `check.sh` runs only while the sequestered folder exists, with `ulimit -t` in front. The suite keeps the rules through a stand-in runner that returns, for example, `{ code = 124, stderr = "at\tspins\t17\n" }`, plus one cheap unmocked case showing `--time <limit>` reaches `bounded.pl`. The executor can add the seam in `hostile.finishes` now, without touching sequestered files: an optional runner argument, or a module field `hostile.run` that the spec replaces (about 10 lines). Cost: one prep round and its review.
- (b) The user accepts 2 × 3 s of spinning `lune` in every full gate, against the c0191 ruling. Cost: none now; the spinners stay.
- (c) Land as is and capture a chore to convert the spec. Cost: the spinners run until that chore lands.

The same decision covers whether `scanners.spec`'s 9.8 s sweep stays in the fast tier. That sweep does not spin when it passes, but zz-test says to "split or stub a spec that takes more than about a second".
Lesson: zz-test/specs-never-burn-real-resources

### F3 [medium] --affected never selects the whole-tree lint or the sweep: the `*` lines in inputs.tsv do nothing
Where: z-nile/tests/inputs.tsv:305-306; z-nile/lib/context.luau:52 (`inputs = {}`); c0193.md, "Where the checks run" (:65-66); R0072.md, Whole-raft design ("c0193's meta case and `tree.spec` read the whole covered tree, so they must be declared as always-run")
Evidence: `lune run z-nile/affected -- <file>` for `z-nile/lib/graph.luau`, `z-nile/engine/raftcheck.luau`, `z-nile/engine/boundcmd.luau`, `z-nile/engine/trace.luau` and `z-nile/engine/main.luau` lists neither `tests/meta/scanning-loops.spec.luau` nor any c0193 spec.
- Spec selection is the watch map (#293; zz-test, Affected selection). `context.load` gives the selector an empty `inputs`, so the two `*` lines change nothing.
- The meta case's `scanning-loops.watch.txt` and the ticket's `acceptance/watch.txt` name only the five helper files.
- So a branch that adds an unlisted loop to any other covered file, or makes a swept scanner spin (graph, paths, ids, skills, raftcheck, boundcmd, trace), passes every `--affected` gate and goes red only at the merge's `--full`.

The Design's "any change under `z-nile/` selects them (`ALL`)" no longer holds, and the raft's "declared as always-run" is not met.
Critique: The author will be tempted to add paths to the watch files by hand. `./zn finish` is their only writer, and a list of today's files misses the next file anyway: a whole-tree rule's inputs are not a list.
Consequences: The watch map has no "every path" form ("Nothing falls back to every spec"), so the real fix is in the selector, outside this ticket. c0192's `inputs.tsv` lines (layer 1) do nothing for the same reason. No gate is weaker than before this raft, and the merge's `--full` still runs everything. The cost is that a broken branch goes red at its merge instead of at its first `--affected` gate.
Recommendation:
- Record in c0193.md, as a deviation under "Where the checks run" quoting the `affected` output above, that the lint and the sweep run in every merge's `--full`, and under `--affected` only when one of the five helpers changes.
- Keep the two `inputs.tsv` lines only with a comment that nothing reads them until c0180, or drop them.
- The lead captures an issue (`./zn new issue c … --project z-nile`) for a watch-map form that selects a whole-tree spec on any change under its roots (c0193's meta, tree and scanners specs; c0192's meta case), and tells c0180's lead, whose AC8 declarations live in the same file.

This records a gap in the selector and changes no behavior, so it needs no spec case.
Lesson: zz-test/specs-read-sources-through-the-selector

### F4 [medium] A text-reading loop whose end the lint cannot find is not asked for a sweep
Where: z-nile/tests/lib/loops.luau:139-140 and :153 (when `last` is nil, `reads` comes from the header alone)
Evidence: Probe on `while i <= #text do / local c = string.sub(text, i, i) / local s = [[ / long (at column 0) / ]] / i = g(text, i) / end`. That is the incident's shape: a helper gives the next position. `loops.find` reports `scansText=false`, and `loops.problems` accepts an entry with a reason and no `sweep` (it reports no problem). The Design (rule 6) treats an end it cannot find as unproven, and that holds. But AC5's "a loop that reads text names its sweep" then depends on a body the lint never read.
Critique: The author may be tempted to scan to the end of the file. That pulls the code after the loop into its body.
Consequences: Failing closed means a loop whose end is not found counts as reading text, so its entry must name a sweep, or `false` with a reason. No loop in today's tree has an end the lint cannot find (probe over 117 files), so nothing turns red.
Recommendation:
- Set `reads = true` when the loop is not one line and `last` is nil, and say so in the comment at the top of `loops.luau`.
- In F1's executor-written spec, add a loop whose body holds a column-0 long string, with no text call in its header: it must report `scansText = true` and need a sweep field.
- Add the converse: a loop whose end is found and that makes no text call stays `scansText = false`, so the "always true" mutant fails.
Lesson: zz-arch/guard-no-is-explicit

### F5 [low] Two `sweep = false` reasons say why the loop ends, not why it needs no sweep
Where: z-nile/tests/lib/loops.luau:569-585 (the `stripComments` and `splitPipeRow` loops of `trace.luau`, at trace.luau:286 and :673)
Evidence: The Design ("What the list holds") says `sweep = false` carries a reason "why none is needed: not callable, shrinking path, a literal needle". Instead, "the local splitPipeRow helper advances past each pipe or breaks" says why the loop ends. `splitPipeRow` is reached through `trace.parse(text)`, a public pure function over a text: the kind of function the new zz-test bullet asks to add as a case. `stripComments` is reached through `trace.deriveClaims`.
Recommendation: Either add a `trace.parse` case whose witness is a `## Claims` table row parsed into one claim, and record its advance-stopping mutant as TR1 was, or reword both reasons to the Design's allowance ("a literal, non-empty needle: `|`", "`<!--` and `-->`").

### F6 [low] The count of loops listed from landed branches is not reported
Where: PR #329's body; c0193.md, Verification log
Evidence: Existing work says that if one of the branches lands before this raft, the executor "lists its loops …, and reports the count in the PR", and step 5 says "say so in the PR". The tree now has 82 loops (5 proven, 77 listed), against 36 (3 proven, 33 listed) at prep. The PR body and the log name the mutants, but not which landed work brought the extra loops or how many.
Recommendation: Add one line to the Verification log and to the PR: the loops at the start by source (prep's 33, c0191's, R0052's, trace's and the others), and that each `why` was read against its loop.

## Judged criteria (code mode only)
- None: c0193 has no Judged criteria.

## Lesson candidates (for the lead)
- F1: in zz-arch, "A line lint that decides 'nothing else writes V' matches every assignment form of the language: the compound operators (`+= -= *= /= //= %= ^= ..=`) and typed declarations (`local v: T =`, `for v: T =`), and counts a form it does not recognise as a write." Check: which assignment forms does the matcher accept, and does a form it does not know prove the loop or void the proof?
- F2: in z-ready or z-raft, "Readying a raft re-reads its members' sequestered files against the lessons added since each member's prep." Check: which lessons landed between each member's prep commit and the ready, and does any sequestered file repeat its defect? (c0193 was prepped 13 hours before specs-never-burn-real-resources.)
- In zz-review code mode item 2, the sequestration diff should name `acceptance/watch.txt` (written by `./zn finish`) as the one addition that is not R100. Otherwise every layer review meets it.
- Specs whose fixtures run `git` from `PATH` (wrapper-guards, repo-fence) fail inside a dispatched session, whose `PATH` starts with `z-nile/bin`: a candidate issue.

Verdict: changes
