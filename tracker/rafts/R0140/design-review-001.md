# Review 001: R0140 (design mode)
Inputs: 705983d (prep-parallel-gate-stages). R0140.md, R0140/check.sh, c0470.md, c0470/check.sh, c0470/acceptance/{parallel-runner,par-stages,spec-isolation}.spec.luau; current scripts/check.sh, tests/run.luau, tests/lib/*.luau, scripts/lib/ac.sh, scripts/tracker/main.luau, .github/workflows/check.yml, every `tracker/issues/*/check.sh` that greps the runner. Ran `scripts/tracker.sh check c0470` on today's code (1/7 pass, AC3 only, each failure an assertion as the doc claims; 74 s), type-checked the three specs with luau-lsp (clean), and ran scratch probes for Lune env inheritance, `math.random` seeding and the `slowest:` match.

### F1 [high] The `slowest:` case fails a correct implementation that prints the file path the design specifies
Where: parallel-runner.spec.luau:202-216; c0470.md Spec runner, Output (`slowest: <file> <s>s, ...`)
Evidence: The fixtures are passed as `.cache/c0470-runner/slow.spec.luau` (repo-relative, like every other runner argument and every `FAIL <file>` line). A design-conformant line is `slowest: .cache/c0470-runner/slow.spec.luau 1.1s, .cache/c0470-runner/fast.spec.luau 0.1s`. The case captures everything after `slowest: ` and asserts `indexOf(line, "slow.spec.luau") == 1`. Scratch run of the spec's own match on that line: `slowAt = 21`. The case passes only if the runner prints a basename (or a path that begins with `slow.spec.luau`).
Critique: The spec is sequestered, so the executor must either deviate from the Design (print basenames, which are ambiguous: the repo has many specs with the same basename, e.g. `place.spec.luau` under f0120 and f0130) or stop and escalate. The tempting fix is to change the design text to "basename", which makes the `slowest:` line useless for finding a spec.
Consequences: Pinning "the path exactly as the runner was given it, as in FAIL lines" also fixes what RC1 greps (`.*\.spec\.luau [0-9]+\.[0-9]s` already accepts it). It means that with absolute-path arguments the runner prints the stripped, repo-relative path, as it does today.
Recommendation: In the Design, state that `<file>` is the repo-relative path as used in `FAIL` lines. In the spec, assert `string.sub(line, 1, #slowPath + 1) == slowPath .. " "` (with `slowPath` = the `rel` path returned by `fixture`), and keep "fast absent or after slow" as a position comparison. Re-run the case against a scratch prototype that prints repo-relative paths.

### F2 [high] parallel-runner inherits the caller's environment, so the documented `PICKMAN_JOBS=1` workaround turns the gate red after promotion
Where: parallel-runner.spec.luau:67-74 (`run`), :107-114 (default case); R0140.md Risks & rollback ("set `PICKMAN_JOBS=1`"); c0470.md Usability; RC2
Evidence: Lune's `process.exec` merges `env` into the parent environment. Probe: under `PICKMAN_JOBS=1 lune run probe.luau`, both `exec(sh, {"-c","echo $PICKMAN_JOBS"})` and the same call with `{ env = { X = "1" } }` print `1`. After `tracker.sh done` promotes the spec to `tests/acceptance/c0470`, `PICKMAN_JOBS=1 scripts/check.sh --full` (the documented rollback, and what the Speed section will tell people to use "for debugging a suspected ordering bug") runs this spec in-process. Its "with no flag the default job count is at least 2" child inherits `PICKMAN_JOBS=1`, runs the rendezvous serially, waits 20 s and fails. RC2 (`PICKMAN_JOBS=1 lune run tests/run`) doesn't catch this, because it runs before promotion, when the spec is not under `tests/`. The same leak applies to any `PICKMAN_RV_TIMEOUT` in the caller's environment.
Critique: The serial fallback is the main rollback lever, and it breaks the gate on day one. The tempting fix is to pass `env = { PICKMAN_JOBS = "" }`, which works only if the runner treats empty as unset, and the Design says nothing about that (see F10).
Consequences: The spec has to control its children's environment. `env -u NAME` exists on macOS and GNU coreutils, so spawning `env -u PICKMAN_JOBS -u PICKMAN_RV_TIMEOUT lune run tests/run -- ...` is portable. Alternatively the Design defines "empty `PICKMAN_JOBS` = unset" and the spec passes `""`, which is a new rule that needs its own case.
Recommendation: Make `run` strip `PICKMAN_JOBS` and `PICKMAN_RV_TIMEOUT` (via `env -u`) before applying the case's own `env`. Add a second line to c0470/check.sh AC1 that runs the same spec under `PICKMAN_JOBS=1`, so the property is pinned after promotion as well, and add a Rules-and-mutants row: "the spec does not depend on the caller's PICKMAN_JOBS", whose mutant is the current `run`.

### F3 [high] AC1's "sums counts across workers" can be passed by counting files instead of cases
Where: parallel-runner.spec.luau:39-43 (`cases` builds exactly one case per fixture); Rules and mutants row "counts are summed across workers"
Evidence: Every fixture has exactly one case, so per-file and per-case counts coincide in every assertion (`2 passed, 1 failed, 3 spec files`, `6 passed, 0 failed, 6 spec files`, …). A coordinator that ignores the worker's summary and does `passed += ok and 1 or 0; failed += ok and 0 or 1` passes all 12 cases. That is exactly the row's listed mutant "count only workers with a non-zero exit", which is not killed. AC6 and RC1 never look at the numbers. On the real suite the summary would read about `70 passed, 3 failed` instead of `450 passed, 5 failed`, and the c0070/c0330/c0360/c0050/c0060 checks that grep the summary shape would not notice.
Critique: This is an acceptance criterion a wrong implementation passes. The summary line is the interface the raft says it keeps fixed.
Consequences: A multi-case fixture needs a `cases`-like helper that takes several bodies. Nothing else changes.
Recommendation: Add a case with fixture `a` holding 3 passing cases and fixture `b` holding 2 passing and 2 failing cases, run with `--jobs 2`, and expect `5 passed, 2 failed, 2 spec files` and both `FAIL <b> :: <name>` lines. Mark that row as killing "per-file counting" through this case.

### F4 [medium] Stage times can be hard-coded or measured wrongly and still pass; the Design doesn't say where a stage's end time is taken
Where: par-stages.spec.luau:104-111; c0470.md Gate stages ("Elapsed time uses `perl -MTime::HiRes`…")
Evidence: The case only requires `quick` to match `%d+%.%ds` and `napping` (sleep 1) to be `>= 1`. A `par_wait` that prints a constant `(1.0s)` for every stage passes. So does the natural wrong implementation that waits in start order and stamps each stage's end time when `wait $pid` returns, rather than when the stage finished: a fast stage started after a slow one is reported as taking as long as the slow one. In check.sh that mislabels `types (tests + scripts)` (0.08 s) as about 1 s, because it is started after `types (src)` (1.08 s). That defeats the "monitor continuously" purpose. The Design never says the end time must be taken inside the background job.
Critique: The timing rule is the point of the Speed section, and it is unpinned. The obvious fix, "assert quick < 0.5", is a banned wall-clock threshold.
Consequences: Use a relative assertion with a full second of margin, which also survives the whole-second `date +%s` fallback.
Recommendation: In the Design, state that each stage's elapsed time is measured by the backgrounded wrapper itself (start and end stamped in the job, written next to its output). In the spec, start `napping sleep 2` first and `quick true` second, then assert `napping >= 2` and `quick + 1 <= napping`. With the fallback, quick ∈ {0, 1} and napping ∈ {2, 3}, so a correct implementation always passes. The constant mutant and the stamp-at-wait-return mutant (quick ≈ 2.0) both fail. Add the row "a stage's time is its own, not the batch's" with that mutant.

### F5 [medium] Nothing checks that `scripts/check.sh` actually runs the static stages concurrently
Where: c0470/check.sh AC4, AC5; Rules and mutants rows for the gate
Evidence: A check.sh that runs the five stages one after another in the foreground, each wrapped to time it and record its exit status, prints the timed headers in order and continues past a failure before exiting 1. It passes AC4 (headers, order, wall time, last line) and AC5 (format FAILED, all five headers, no tests, no GATE PASSED) without ever sourcing `par.sh`. par-stages proves only the library.
Critique: The raft's title behaviour, concurrent gate stages, has no check. The tempting fix is a timing assertion on the gate, which is banned and machine-dependent.
Consequences: A structural proxy pins the implementation shape that the Design already fixes (it names `par_start`, `par_wait || exit 1` and the labels), so there's no new decision.
Recommendation: Add to AC4 (or a new AC) a deterministic grep: `scripts/check.sh` sources `scripts/lib/par.sh`, has exactly five `par_start` lines carrying the five labels in order, and has a `par_wait || exit 1` line before `stage "tests`. Add a mutant row: "serial timed stages in check.sh".

### F6 [medium] The "runs exactly once" guard is a check-then-write race, so a lane-duplication mutant can pass
Where: parallel-runner.spec.luau:60-63 (`ONCE`), :182-200
Evidence: `ONCE` does `if isFile(marker) then error end; writeFile(marker)`. Take the plausible mutant where each lane walks the whole list (no shared index). Both lanes start file *i* at nearly the same moment, and each worker checks the marker before the other writes it, because both are in the same Lune startup window. Both pass. If outcomes are stored per file (the `merge(outcomes)` shape in the Design invites `outcomes[file] = …`), the summary is `6 passed, 0 failed, 6 spec files` and every marker exists. The case passes. Under different timing the same mutant fails, so it's a flaky kill, not a kill.
Critique: The row "a lane that re-runs a file" is claimed killed and isn't, reliably.
Consequences: Lune seeds `math.random` per process (verified: three runs, three different values), so a per-run unique marker is cheap and race-free.
Recommendation: Have each run write `ran-{i}-{math.random(1, 1e9)}` (no check), then assert that exactly one `ran-{i}-*` file exists for each *i*. That kills duplication whatever the timing or the merge shape.

### F7 [medium] Rows and cases missing for worker-exit edge cases; one row claims a kill it can't get
Where: c0470.md Merge ("A worker that reported `0 failed` but exited non-zero is also one failure"; "no such line is one failure"); Rules and mutants rows "A worker with no summary line…" and "A single file runs in-process"
Evidence:
(a) The only dead-worker case exits with code 3. A worker that calls `process.exit(0)` mid-case (no summary, exit 0) is the dangerous one: today's in-process runner silently passes with no summary in that situation. The mutant "missing summary is a failure only when the exit code is non-zero" survives.
(b) The "reported 0 failed but exited non-zero" rule has no row and no case.
(c) The row "always spawn a worker" for the single-file rule can't be killed by `a single spec runs in-process`: a coordinator that spawns one worker and strips its summary prints the identical `1 passed, 0 failed, 1 spec files\n`.
(d) The default `min(max(cpus,2),8)`: only ">= 2" is pinned, so "default is always 2" survives. That's a 4x slowdown on an 8-core host, visible only in OC1.
Critique: The table is presented as complete ("each row kills one"), and three of these are silent.
Consequences: (a) needs one fixture. (b) is hard to produce from a fixture, because a worker that prints its summary then dies is hard to stage. (c) and (d) are behaviour-equivalent or performance-only.
Recommendation: Add the case `cases('require("@lune/process").exit(0)')`, expecting `FAIL <file>: worker exited with code 0` and one failure. For (b), either drop the rule from the Design or mark it `reasoned, no case` with the reason. Re-mark (c) as "not observable by output; reasoned only". Record (d) in the table as covered by OC1 only.

### F8 [medium] The new specs break the Speed rule this issue writes, and the runner spec approaches the measured 9.3 s floor
Where: c0470.md Speed rule ("no sleeping or polling on wall-clock time", "split … a spec that takes more than about a second"); parallel-runner.spec.luau (`RENDEZVOUS` with `os.time()`, `SLEEP1`); par-stages.spec.luau (`sleep 0.5`, `sleep 1` twice)
Evidence: parallel-runner has two serial-timeout cases. Each takes 2-3 s, because `os.time()` has 1 s granularity and the limit is `os.time() + 2`. Two cases sleep 1 s, and every case spawns nested `lune` processes. Estimated 8-10 s for the file, a single lane, which is comparable to `c0041/worktree.spec.luau` (9.3 s), stated as the suite's floor. par-stages adds about 3 s of sleeps. Once promoted, both sleep and poll on the wall clock in every full gate, which the Speed section the same issue adds forbids.
Critique: Either the rule or the specs is wrong as written, and the next spec author will cite these files.
Consequences: The serial-timeout cases can use a short timeout safely: a correct implementation always fails them, whatever the speed, so a short timeout only makes them faster. The concurrent cases must keep the long timeout.
Recommendation: Poll with `os.clock()` (wall time per E5) and set `PICKMAN_RV_TIMEOUT = "0.5"` for the two serial cases. Split parallel-runner into two files (the rendezvous and default-count cases, and the merge and format cases) so they occupy different lanes. Word the Speed rule as: no wall-clock assertions; sleeps and polling only in specs that test concurrency, as a rendezvous with a timeout.

### F9 [low] The eager-start case passes a correct implementation only if `touch` starts within 0.5 s
Where: par-stages.spec.luau:48-54
Evidence: `par_start mark touch …; sleep 0.5; [ -e started ] && echo started-before-wait`. During a full gate with 8 lanes, plus nested Lune processes from parallel-runner, on a 2-vCPU CI runner, a fork and exec delayed past 0.5 s makes a correct `par.sh` fail. This is the wall-clock dependency the design replaced elsewhere with rendezvous.
Recommendation: Poll for `started` for up to 20 s before calling `par_wait` (`for i in $(seq 1 400); do [ -e … ] && break; sleep 0.05; done`). The start-in-`par_wait` mutant still times out and fails, and a correct implementation passes as soon as `touch` runs.

### F10 [low] Points where two implementers would diverge
Where: c0470.md Spec runner, Gate stages
Evidence and decisions needed:
- A `PICKMAN_JOBS` value that is empty, `0` or `many`: usage error with exit 2, or ignore it and use the default? (This interacts with F2.)
- Does the in-process path (`--jobs 1`, several files) print `slowest:`? "byte-identical output" says no; "(when more than one file ran)" says yes.
- May `--jobs N` appear after file arguments (`-- a.spec --jobs 2`)?
- Is a worker's stderr re-emitted on stdout or stderr?
- How is `gate wall time` measured: from script start, and with the same perl/`date` helper as `par.sh`?
Recommendation: Answer each in one line in the Design. Add a case for the `PICKMAN_JOBS` answer, and for `slowest:` under `--jobs 1` if it's meant to print.

### F11 [low] par-stages never runs the library under check.sh's `set -euo pipefail`
Where: par-stages.spec.luau:23-30; scripts/check.sh:7
Evidence: The spec sources `par.sh` in a plain `bash -c`. Two bash-3.2 traps under check.sh's options go unseen there: `"${arr[@]}"` on an empty array is an unbound-variable error under `set -u` in bash < 4.4 (for example an empty batch, or iterating after a reset), and `(( n++ ))` with n=0 returns 1 and aborts under `set -e`. AC4 and AC5 catch only the paths check.sh exercises, and only on macOS: CI's `/bin/bash` is 5.x, as the table admits.
Recommendation: Prefix the spec's scripts with `set -euo pipefail` (the cases already put a failing `par_wait` last or after `||`), and add a case for `par_wait` on an empty batch, which must return 0 and print nothing.

### F12 [low] The `.cache/sim` exemption rests on a claim that isn't true
Where: R0140.md Risks ("a collision would only rewrite an identical file"); spec-isolation.spec.luau `SHARED_BY_DESIGN`
Evidence: Replay files are named `<model.name>-seed<s>-tick<t>.json`, and model names aren't unique across spec files: `drunk` is a different model in c0090 `determinism` and `replay`, and `walker` appears in c0090 `expect`, c0090 `script` and `tests/fixtures/sim`. Today no two concurrently running files write and read the same replay name. c0090 `expect` reads back `walker-seed1-tick2.json`, which only it writes. So nothing fails today, but a future failing Walker scenario at seed 1, tick 2 would race c0090's read of a non-atomically rewritten file. The scanner also sees only literal `.cache/<dir>` text in `*.spec.luau`, not paths built at runtime or written by helpers and scripts.
Recommendation: Correct the Risk text (collisions are possible, and harmless only if the writers' contents match). Note the scanner's literal-path limitation in the Speed section. Optionally, have specs that read back replays use a model name unique to their file. That's a one-line rename, not this raft's scope unless cheap.

Verdict: changes
