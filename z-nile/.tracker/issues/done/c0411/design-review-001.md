# Review 001: c0411 (design mode)
Inputs: 98301d199 (prep-rounds-spec-reads-every-root, merge base 1d9e5952 with origin/main bf584e613; no engine, test or registry file differs between them). Files: c0411.md, check.sh, acceptance/narrow.py, experiments/prototype.patch, experiments/E5-rounds-roots.spec.luau, experiments/E2-narrow-mutants.sh, experiments/E2-narrow-results.txt, guesses.md, idea-review-001.md, idea-refute-001.md; `./zn capture c0411`; d0406 on origin/main and in `.worktree/prep-metrics-reads-idea-spend-rows` (read only). Runs: `./zn check c0411` (FAIL AC1 at line 7, PASS AC2, as E7 records); `narrow.py` on a scratch copy of rounds.spec with prototype.patch applied (`the base 1d9e5952 with exactly the two c0411 hunks`, rc=0).

### F1 [high] The captured outcome "retired.spec passes without being edited" is checked by nothing, and the design's claim that d0406's check runs it is contradicted by d0406's own draft
Where: c0411.md Design, "Order and how the three captured outcomes are checked" (line 46: "d0406's own check (its AC that `rounds.spec` and `retired.spec` pass on the slow tier) is where the passing run is checked"), Existing work (line 51), check.sh lines 12-14; Solution bullet 3 of the capture.
Evidence: the capture's third Solution outcome is "With d0406 fixed and this change in place, `z-nile/tests/acceptance/c0116/retired.spec.luau` passes without being edited." c0411's AC2 checks only "unedited". The pass is handed to d0406, but d0406's check.sh in its prep worktree (`.worktree/prep-metrics-reads-idea-spend-rows/z-nile/.tracker/issues/d0406/check.sh`) says the opposite: "A slow-tier spec, run once here on purpose (4 s measured, 2026-11-17) ... retired.spec (110 s) is not." and its only spec run is AC7 `lune run tests/run -- tests/acceptance/c0043/rounds.spec.luau`. Both specs are in `z-nile/tests/slow.tsv`, so no `--affected` or `--full` gate runs them either. After both items land, nothing has run `retired.spec` on the merged code; the only evidence is E6, a one-time run on a scratch worktree (now removed) holding d0406's prototype, not d0406's landed fix.
Critique: an outcome the Problem names (retired.spec red on main) is left without any Checked criterion and without the Verification-log run the slow-tier lessons allow in its place. The tempting fix is to reword line 46 to say "d0406's check runs rounds.spec" and drop retired.spec from the sentence, which silently drops the outcome; or to add a `lune run` of retired.spec to c0411's check.sh, which cannot pass while d0406 is unlanded (G4's order).
Consequences: whichever item carries the run pays retired.spec's time, and the two preps disagree on it (E6 measured 281.6 s; d0406's comment says 110 s). A check.sh line pays it at every `finish`, `restack` and `done` (lesson zz-test/check-sh-never-runs-the-slow-tier); a once-run Implementation step with a Verification-log quote pays it once but is not a check, so the code reviewer must be told to look for the quote. If the run lives in d0406, d0406's design changes, which c0411's prep cannot make alone.
Recommendation: before approval, get the run into a committed document and quote it here: either (a) d0406's design gains an Implementation step that runs `z-nile/check.sh --slow -- tests/acceptance/c0043/rounds.spec.luau tests/acceptance/c0116/retired.spec.luau` once on its finished layer (on the stack with c0411 landed), with its Verification log quoting `PASS` for both and the measured seconds, or a check line for retired.spec with its measured seconds beside it; or (b) z-raft puts c0411 and d0406 in one raft, c0411 first, and the raft's final step carries that one `--slow` run. Then rewrite line 46, line 51 and check.sh's comment to quote the line d0406 (or the raft) actually holds, with one measured time. If d0406's lead declines both, this is escalate to the user: keep the outcome (cost: one 110-280 s run, once or per step), or record a `Scope decision (user, ...)` line; do not drop it here.
Lesson: z-design/guards-name-slow-tier-specs
Erred: z-design
Upstream: none

### F2 [medium] The landing order G4 depends on (d0406 `depends_on: [c0411]`) exists in no document, so nothing stops d0406 being readied first
Where: c0411.md Design, Order (line 43) and Existing work (line 51: "**d0406** (preparing) carries `depends_on: [c0411]`"); guesses.md G4 ("d0406 will carry depends_on: [c0411]").
Evidence: `git show origin/main:z-nile/.tracker/issues/d0406/d0406.md` has `depends_on: []`, and so does d0406.md in its prep worktree today. `ready` reads only a member's own `depends_on`. If d0406 is readied and executed first, its AC7 (`rounds.spec passes on the real tracker`) runs the unedited case, which E1 shows fails with `expected deep-equal values`, and d0406's executor may not edit the sequestered spec nor this chore's file: it stops, and the order is fixed only after a stop and a re-plan.
Critique: the design states another prep's front matter as fact while that prep has not written it. The tempting fix is to soften "carries" to "will carry", which leaves the order still unenforced.
Consequences: the edge has to be written by d0406's prep (c0411 has no `depends_on` to add: the edge points the other way), so c0411's approval depends on another prep's commit; if the two are rafted together (F1 option b), the raft's Order must state it too.
Recommendation: before this design is approved, confirm the edge is committed on d0406's prep branch (or in the raft document that groups both) and quote that line and commit in Existing work; until it is, list it under `## Open to the human` as a precondition of G4 rather than state it as present.
Lesson: z-design/quote-other-preps-before-promising
Erred: z-design
Upstream: none

### F3 [low] Stale cross-references in the document and experiments
Where: c0411.md line 48; line 90 (E5 Method); line 85 and 89; experiments/E2-narrow-mutants.sh line 2.
Evidence: line 48 says "The other three cases of `rounds.spec` and the sandbox case stay byte for byte (AC2)": AC1 pins them (AC2 is retired.spec), and the sandbox case is one of the three. E5's Method says "`acceptance/rounds-roots.spec.luau` copied", but the file is `experiments/E5-rounds-roots.spec.luau` (G2's promoted spec was dropped by G4). E4's script and results are named `E2-narrow-*`, and the script's header says it is "the prep mutation check for AC2 (acceptance/narrow.py)", which is AC1. Every run is recorded in `.worktree/scratch-c0411`, which no longer exists, and nothing says how to rebuild it (origin/main plus which d0406 patch).
Critique: an executor or a later re-prep following these references reaches the wrong criterion, a file that does not exist and a worktree that is gone.
Consequences: none beyond the text; the rebuild recipe names d0406's prototype, which lives in another prep's folder and can change.
Recommendation: say AC1 on line 48 and drop "and the sandbox case"; point E5's Method at `experiments/E5-rounds-roots.spec.luau`; rename the E2-narrow files to E4 (or call the experiment E2 in the document) and fix the script's "AC2"; state how the scratch tree is rebuilt (origin/main at the recorded sha plus `prep-metrics-reads-idea-spend-rows`'s d0406 diff on `ledger.luau` and `main.luau`, at a named commit).
Erred: z-design
Upstream: none

### F4 [low] E5's "passes" verdict is only "no deep-equal FAIL line", so a case that errors reads as passing
Where: experiments/E5-rounds-roots.spec.luau `caseFails` (lines 93-98) and its first case (lines 104, 117).
Evidence: the first case proves the captured "keeps passing when a project root or a raft is added" by `caseFails(added) == false`. A rounds.spec whose case raises (for example `projects.load(TOP .. "/x")`: "no z-nile/projects.toml") prints a FAIL line for the case with that error and no "expected deep-equal values", so `caseFails` is false and the case passes; so does a run that never loads the spec.
Critique: the positive half of the proof rests on the absence of one message, not on a pass. AC1's byte pin keeps such a mutant from landing, so the shipped file is not at risk; the recorded proof is weaker than it reads.
Consequences: a stricter verdict needs the runner's summary format (`N passed, 0 failed, 1 spec files`), which E2 already quotes.
Recommendation: judge a pass by the run's summary showing `0 failed` and `1 spec files` and no FAIL line naming the case; rerun E5 once (about 2 minutes) and record its output.
Erred: zz-test
Upstream: z-design

### F5 [low] The prep's own probe runs are not recorded as bounded
Where: c0411.md Unknowns & experiments E4 (`experiments/E2-narrow-mutants.sh`), E7.
Evidence: E4's Method runs the shell script (eleven `python3 narrow.py` calls and `git` reads) with no `./zn run --time` around it, and the script's header says "Run from the scratch worktree's root" with no bound. The spec-runner runs (E1, E2, E5, E6) and `./zn check` are exempt; this script is not.
Critique: a rerun by a later prep follows the recorded command.
Consequences: none.
Recommendation: record E4's command as `./zn run --time 120 -- bash experiments/E2-narrow-mutants.sh <folder>` (and say so in the script's header).
Erred: z-design
Upstream: none

Verdict: changes
