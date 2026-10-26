# Review 001: c0154 (design mode)
Inputs: prep `prep-gate-slow` 71809941 (c0154.md, check.sh, acceptance/{schedule.spec,durations}.luau, experiments/{schedule.luau,run.patch}); capture a0ac545e (`./zn capture c0154`); c0157 on origin/main; `./zn lessons --when design --full`. The prototype (run.patch + schedule.luau) is applied in a scratch clone of 71809941 (scratchpad `dr-chores-2/c0154`).

Checked and holding:
- Repository safety of the new `.cache/spec-durations.tsv` write. `fence.enter()` re-runs the whole runner, coordinator included, under the jail on macOS, so a spec that swaps the record for a symlink to a repository file has the write refused by the kernel (and swallowed by the `pcall`). The next run's `fence.enter` unlinks top-level `.cache` symlinks before anything reads them. On Linux everything is unjailed already, so this adds nothing there.
- The in-process path is untouched (`--jobs 1` neither reads nor writes the record).
- The sort comparator is a strict total order over distinct paths, so `table.sort` being unstable can't change the result.

### F1 [medium] duplicate file arguments now lose outcomes: the counts and the `slowest:` line change
Where: run.patch, `indexOf[f] = i` and `outcomes[index]` (`local index = indexOf[file]`); AC4 ("reports in path order with unchanged counts and exit code"); Regression guard.
Evidence: in the clone, `lune run tests/run -- --jobs 2 tests/acceptance/c0001/ci-workflow.spec.luau tests/acceptance/c0001/ci-workflow.spec.luau` gives the following.
- On the original runner: `slowest: … 0.1s, … 0.1s` and `12 passed, 0 failed, 2 spec files`.
- With the prototype: `slowest: ` (empty) and `6 passed, 0 failed, 2 spec files`.

Both runs of the duplicate write `outcomes[2]`, so `outcomes[1]` is a hole. The runner doesn't deduplicate its arguments. A file that fails once and passes once could also report only the pass.
Critique: the queue is keyed by path, and paths aren't unique in `files`. The tempting fix is deduplicating `files`, which changes what a caller that lists a file twice gets today.
Consequences: none if the queue carries indices.
Recommendation: schedule indices instead. `schedule.order` returns positions into `files` (or the runner orders `{index, file}` pairs), and each lane writes `outcomes[index]`. Add a Rules row and a schedule.spec case (one spec file passed twice prints the same counts as the old runner, `2 spec files` and twice the cases), with mutant "outcomes indexed by path", run.

### F2 [medium] the runner case's timing assertions can flip under the load these gates run at
Where: schedule.spec "the runner starts the slowest recorded file first …". It uses `rec["tests/c.spec.luau"] > rec["tests/a.spec.luau"]` (sleeps 0.6 s against 0.1 s), and run 3's `firstStarted(2) == { "c", "n" }` depends on that measured record. It also uses `firstStarted(2)` start-time comparisons with 0.1 s sleepers.
Evidence (reasoned from the spec and the Design's own measurements): each recorded duration is the whole `lune run tests/run -- --jobs 1 <file>` process. At load 13–24, process start-up varies by more than a second (the Design measured a `./zn` call at 0.3 s idle and 2.0 s average under load). A 0.5 s gap can therefore invert. If `a` is then recorded slower than `c`, run 3 starts `{a, n}` and the case fails.

The same applies to start-time order. With 0.1 s sleepers, the third file can start (`n` ends, then `a` loads) before `c`'s process has reached its case, if `c`'s start-up is slower than `n`'s whole run plus `a`'s start-up. The prototype's "three runs, no flake" were at loads that the next contended gate exceeds.
Critique: lesson zz-test/no-vacuous-pass's sibling. A promoted spec that runs in every gate must not depend on wall-clock margins smaller than the jitter of the machine it runs on (zz-review code mode, "depend on the wall clock"). The tempting fix is longer sleeps everywhere, which makes every gate slower.
Consequences: an input the case writes itself makes run 3 deterministic. Only the "first two to start" checks still use time, and they need a margin larger than start-up jitter.
Recommendation: before run 3, write the record by hand (`c` 100 s, `a` and `b` 1 s). Keep the first run's measured record only for "every file recorded, with a number". Make the files that must hold their lanes sleep ≥ 3 s, so a third file can only start after that. Alternatively, have the sleepers log a start sequence number through an append-only file and compare which two names come first. Rerun the case five times at the machine's current load and record it in E3.

### F3 [medium] each fresh worktree's first gate gets no benefit, and most gates run in fresh worktrees
Where: Design 2 (the record is the home's `.cache/spec-durations.tsv`) and 3; E2/E3; JC1.
Evidence: `.cache` is per checkout and ignored, and every prep, raft and capture works in a new worktree under `.worktree/`. That worktree's first concurrent gate finds no record and runs in path order, the 214 s case. An `--affected` run records only its subset, so a later full gate starts the unrecorded rest first, in path order, ahead of the recorded slow ones. claims.spec and finished.spec, if not yet recorded, are then in path position among the unrecorded.
Critique: the Problem is the gate's wall time. The −24 % holds only from the second full run in each checkout, which the Design doesn't say, and JC1's procedure ("path order forced by deleting the record, then the record kept") hides it.
Consequences: a seed must come from somewhere the branch's tree can't make worse. Reading the main checkout's record is a read outside the checkout, which the jail allows. A tracked seed file would also reach CI, which G2 decided against changing.
Recommendation: when the home has no record, read the main checkout's record (`git rev-parse --git-common-dir`'s worktree, the same home's `.cache/spec-durations.tsv`) through `schedule.parse`. Say so in the Design and add a case in a fixture with two worktrees. If the author prefers not to, say plainly that the first full gate of each worktree stays in path order, and let JC1 measure a fresh worktree's first run too.

### F4 [medium] JC1 may never be measurable on this machine, and one sample of each order can't separate a 15 % gain from load drift
Where: JC1 rubric; Verification log ("JC1's clean measurement is left for execution in a quiet window").
Evidence: the prep's own comparisons were 296.1 s against 336.3 s with the load moving from 3.6 to 26 and back. JC1 takes one run of each order and voids the comparison when the loads differ by more than 3, with no limit on retries. Until c0157 lands, a quiet window is not something the executor controls.
Critique: a Judged criterion the executor can't bring to a ruling stalls the raft (lesson z-design/instructions-runnable-where-they-run). AC3 already is the measurable proxy for the gain.
Consequences: the rubric needs a bounded procedure and an outcome for "no comparable window".
Recommendation: run z-nile's tests stage four times alternating (path order with the record removed, then the record kept, A B A B) with `PICKMAN_JOBS=8` set explicitly. Compare each adjacent pair whose load averages differ by ≤ 3, and pass on the median gain of the valid pairs ≥ 15 %. With no valid pair after three attempts, record the runs and escalate (zz-execute stop conditions) rather than retrying indefinitely.

### F5 [low] the record is written non-atomically, by nested runners too, and an empty read rewrites it empty
Where: run.patch (`fs.writeFile(DURATIONS, schedule.render(recorded(), runs))`, always, even when `runs` is empty); `schedule.parse("")` returns `{}`, not nil.
Evidence: E4 says c0470's runner spec runs nested runners from this home, so they write the home's record during the outer run. One nested run reading while another truncates gets `""`, which parses to `{}`, and writes back an empty record. A later `--affected` run then merges into an almost empty record. The harm is ordering only, and the record also keeps every renamed or deleted spec's line forever.
Recommendation: write only when `runs` is non-empty, write to a temp file in `.cache` and rename it (z-nile/lib/replace-file.pl or `fs.move`), and drop lines whose file no longer exists under `tests/` when rendering a full run. Add a case: a run naming only fixture files leaves the record byte for byte.

### F6 [low] M4's "reasoned" row is in fact killed, but only by the no-record assertion: a tie-break dropped only among recorded files survives
Where: Rules and mutants row "ties by path".
Evidence: with the tie-break replaced by `return false`, the spec's first case gives `a.spec f.spec c.spec b.spec d.spec e.spec` (the recorded tie b/d passes) and `b a c` for the no-record assertion, which kills it. A mutant that keeps `a < b` for unrecorded pairs but returns `false` for equal recorded durations passes both. On 12 tied recorded files given in reverse path order, the `return false` comparator returns `t12 t05 t06 t04 t03 t02 t07 t09 t08 t11 t10 t01`.
Recommendation: mark M4 `run` and add a recorded-ties input in reverse path order (for example 12 files at one duration) to the first case, expecting path order. Name the second mutant.

### F7 [low] the record still says the lane count changes, and the capture didn't hold the ideas G1 says it set aside
Where: Regression guard ("only the order files start in and the default lane count change"); G1 ("the capture's ideas (shared fixtures, splitting the two specs) are not taken").
Evidence: the Design keeps `min(max(cpus, 2), 8)` (load-sized lanes dropped), and run.patch doesn't touch the lane count. The capture (a0ac545e) has a Problem line only: no Solution, and no outcome beyond "the full gate slowed to ~520 s … dominate".
Critique: lesson z-design/decided-guesses-rewrite-their-body. A stale sentence from the dropped design, and a decision text that misattributes its premise to the capture.
Recommendation: fix the Regression guard sentence. Reword G1's premise to "the prep's first ideas (shared fixtures, splitting the two specs)". The user's answer stands.

Scope fidelity: the capture's one outcome is that the gate is no longer ~520 s, with those two specs dominating. Its measured cause, contention between concurrent gates, is deferred to c0157 by G3, a `Decided with the user (2026-10-25)` line, and c0157 exists on origin/main with that scope. Leaving the two specs' own cost alone is G1's. So nothing was narrowed without the user. The capture contains no "under ~200 s" target: if the user meant one, it was never captured, and c0154 alone doesn't reach ~200 s on a contended machine (the 520 s case). Consider copying G3's line into the Problem so a reader of the Problem sees where the 520 s case went.

Candidate lessons (for the lead):
- zz-arch: "A scheduler that reorders work keys its bookkeeping by position, never by name, because names in an argument list need not be unique (c0154: `tests/run -- a a` lost an outcome); check: can the same input appear twice, and what does the reorder do to the second?"
- zz-test: "A promoted case that compares measured durations or start times keeps its margin above the process start-up jitter of a loaded gate, or writes the timing input itself; check: at load 20, can this margin invert?"

Verdict: changes
