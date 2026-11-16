# Review 001: R0081 (code mode)
Inputs: branch R0081-reuse-test-results at ecc0adaf; `git diff origin/main...HEAD` (41 files, +2155/-179); R0081.md; c0165.md (Design, Rules and mutants, Verification log); c0165 `check.sh`, `acceptance/`, `declared/`; raft `check.sh`. Runs: `./zn check c0165` 15/15 PASS (58.8 s, lune 0.10.5). Not run: `z-nile/check.sh --full` (per the brief; the executor's Phase 3 run is in the Verification log). Probes and mutants ran in a scratch clone of ecc0adaf under the session scratchpad, through `./zn run`; the worktree was not touched.

Sequestration: `git diff --find-renames=100% --name-status origin/main...HEAD -- '*/.tracker/**/check.sh' '*/.tracker/**/acceptance/**'` lists three `M` (`acceptance/gatefix.luau`, `acceptance/proof-interim.luau`, `check.sh`), the user-approved edits. Each is minimal and correct: gatefix reads `process.args[#process.args]` in its two lines and nothing else; proof-interim wraps the same two blocks in two `it` cases with the assertions byte for byte; AC15 drops `./zn run --time 600 -- lune run` for `lune run tests/run --` (the runner needs no wrapper, and the file is still no `*.spec.luau`, so it is not discovered after promotion). The four Overrides change only `"--graph-only"` and the one gate-cover digest (AC11 and AC12 pass).

Mutants run (scratch clone, the named sequestered spec run against the mutated code): R33 (exit ignored), R43 (omitted result not failed), R47 (`gate-record` checks the first home only), R71 (trap removes every marker), R28 (gate-check exit 0 alone), R53 "HEAD never", R52 (HEAD in every spec fingerprint), R69 (prune never called), R31 (`stands` ignored), R60 (ref specs added for any project): each failed its case. R53 "HEAD always": survives (F3).

### F1 [high] `resultsdb.rows` crashes the orchestrator, and so the affected gate, on a current sqlite3 or on any sqlite error, instead of turning reuse off
Where: `z-nile/lib/resultsdb.luau:105-131` (`rows`), `z-nile/specs.luau:188` (the unguarded call)
Evidence: `rows` asks for `json_object('rows', (SELECT json_group_array(...)))` and iterates `(v :: any).rows` as an array. Whether a scalar subquery keeps the JSON subtype depends on the SQLite version: `echo "SELECT json_object('rows', (SELECT json_group_array(json_object('a',1)) FROM (SELECT 1)));" | sqlite3 …` prints `{"rows":[{"a":1}]}` on macOS's 3.51.0 (and on 3.39.4, 3.43.1 and 3.50.4, the SQLite builds the installed Pythons link), but `{"rows":"[{\"a\":1}]"}` on Homebrew's 3.54.1 (`/opt/homebrew/opt/sqlite/bin/sqlite3`). In the scratch clone, `lune run z-nile/specs -- run --project z-nile -- tests/acceptance/c0067/paths.spec.luau` ran and recorded (`3 passed`, rc 0); the same command with `PICKMAN_SQLITE3=/opt/homebrew/opt/sqlite/bin/sqlite3` printed `resultsdb:121: attempt to iterate over a string value` with the stack through `specs, Line 188`, and exited 1 without running the spec. `gatePassed` (line 194) already decodes the string form, so the code has two readers of the same answer that disagree. Separately, `rows` calls `error(err)` on any failed call (a busy timeout past 10 s, a corrupt file opened after `open`), and `specs.luau:188` does not `pcall` it, so a db fault fails the gate.
Critique: the Design's rule (R13, Guards: "Any failure of the reuse machinery runs specs rather than skipping them"; "`open` failing ... is never a gate failure") is broken: a newer `sqlite3` on PATH, or `PICKMAN_SQLITE3`, or a macOS update that moves the system sqlite past 3.51, makes every affected gate with a non-empty selection fail before it runs a spec. The tempting fix is to copy `gatePassed`'s `type(...) == "string"` branch into `rows`.
Consequences: a third copy of the tolerance (every future query the c0238/c0240 schema raises must remember it), and a `pcall` around `rows` alone still leaves the next unguarded call to fail the gate.
Recommendation: make the SQL independent of subtype passing (wrap each nested subquery in `json(...)`, e.g. `json_object('rows', json((SELECT json_group_array(...) ...)))`, which re-parses the text into JSON at the outer level on every version) or decode nested text in one place in `call`, so `rows` and `gatePassed` share one reader (zz-arch/one-reader-per-format). In `specs.luau` run `resultsdb.rows` under `pcall` and on failure print `reuse off: <reason>` and run every given spec without recording. Add an unsequestered tooling spec (with its AC14 `added-audited.tsv` line) whose `PICKMAN_SQLITE3` is a stub under `.cache` that (a) answers the string form, where `rows` must return the row, and (b) exits 1 on the rows query, where `specs run` must run the spec, print `reuse off`, and exit 0.

### F2 [medium] `reuseplan.records` never records on Linux: it compares with a jail name the runner never writes
Where: `z-nile/lib/reuseplan.luau:30` (`startsWith(jail, "none (not macOS)")`); `z-nile/tests/lib/fence.luau:676`
Evidence: the runner's only off-macOS name is `"none (not macOS: environment guards only)"` (`fence.luau:676`), exported as `PICKMAN_TEST_JAIL` and written into the results. A probe of the shipped `reuseplan`: `records("none (not macOS)", "linux")` → `true` (the literal `plan.spec` uses), `records("none (not macOS: environment guards only)", "linux")` → `false`. So on Linux every run prints `not recorded: none (not macOS: environment guards only)`, writes the no-record marker (`specs.luau:254-259`), and no spec row or whole-gate row is ever recorded. The Design says `records` is true "for an unjailed run on a non-macOS host (`os ~= "macos"` and the jail starts with `none`)".
Critique: fail closed, so not a forged pass, but the Problem's Reuse outcome silently does not exist on Linux, and AC5's pure case is passed by the wrong implementation because it feeds a literal instead of the producer's text. The tempting fix is to change the literal to `"none (not macOS:"`.
Consequences: a second hand-copied string that drifts the next time `fence.luau` rewords its note.
Recommendation: take the name from its producer: export the off-macOS jail name as a constant from `fence.luau` (one line, a guard-adjacent change review reads) and have `reuseplan` match `startsWith(jail, "none")` on a non-macOS host as the Design states, which keeps `plan.spec`'s literal true. Add an unsequestered tooling case that asserts `reuseplan.records(<fence's exported name>, "linux") == true`, so a rewording on either side turns it red.
Lesson: zz-test/seed-every-enumerated-case

### F3 [medium] Nothing pins "HEAD is in the whole-gate digest only for a `*` selection": the "HEAD always" mutant of R53 passes
Where: `z-nile/specs.luau:365` (`if starred then`); `acceptance/gate-refs.spec.luau`; Rules and mutants R53 (`reasoned`, mutant "HEAD always, or never")
Evidence: with `if starred then` replaced by `if true then`, `lune run tests/run -- .tracker/issues/active/c0165/acceptance/gate-refs.spec.luau` in the scratch clone: `2 passed, 0 failed, 1 spec files`. Both gate-refs cases have a `*` or `ref:` spec selected; no case commits the same content with no `*` spec selected and expects the whole gate reused. ("HEAD never" fails as it should.) The Design also says the `reasoned` rows' mutants are run by the executor ("the executor runs those mutants against its code"), and the Verification log records none.
Critique: a digest that always holds HEAD makes every commit, rebase or pull lose whole-gate reuse for pickman-only and game work, which is the saving the issue exists for, and the gate stays green.
Consequences: none beyond the new case.
Recommendation: add an unsequestered case (a tooling spec on `gatefix`-style fixtures, or on `specs digest` directly): an edit selects only non-`*` specs, `--affected` passes, then `git commit -qam` the same content: the second gate is `reused`; with a `*` spec selected it is not (the existing half). Run the remaining `reasoned` rows' mutants (R27, R43, R47, R52, R56, R60, R62 to R64, R66 to R69, R71, R76) and record which case killed each in the Verification log; this review ran ten of them (Inputs).

### F4 [medium] Recording costs one `sqlite3` process and one `git rev-parse` per spec: about 11 s on an ALL run, where the Design asks for one call
Where: `z-nile/specs.luau:261-296` (the record loop); `z-nile/lib/resultsdb.luau:134-165`
Evidence: inside the loop, each spec calls `workspace.gitState(ROOT, …)` (a `git rev-parse HEAD`, plus its refs) and `resultsdb.record` (one `sqlite3` process), then `prune` makes another. Measured in a probe on this machine: 400 `resultsdb.record` calls took 3.54 s, 400 `git rev-parse HEAD` in this worktree 7.50 s. z-nile has 206 spec files and pickman 269 (`find <home>/tests -name '*.spec.luau' | wc -l`), so an `--all` run of both pays about 13 s after the specs, plus a second `fingerprint.of` per spec. The Design: "The records, and `prune(db, now)`, go in one `sqlite3` call" and Scalability "one `sqlite3` call per phase, not per spec". No deviation is recorded.
Critique: an issue whose purpose is gate time adds a fixed cost to every run that runs many specs. The tempting fix is to batch only the SQL.
Consequences: the git reads are the larger half; batching SQL alone saves a third.
Recommendation: read `gitState` once after the run for the union of the run's declared refs (as before the run), compute each fingerprint from it, and record every row plus `prune` in one `sqlite3` call (one SQL text, `BEGIN; … COMMIT;`, so a failure records nothing). Pin it in an unsequestered tooling case with a counting `PICKMAN_SQLITE3` wrapper under `.cache`: a run of three specs makes one write call.

### F5 [low] Orchestrator and gate output differ from the Design in five places, none recorded as a deviation
Where: `z-nile/specs.luau:237-307`, `:419`; `pickman/check.sh:3`; `z-nile/lib/select.luau:18`
Evidence: no `reuse: <r> reused, <n> ran` line (step 4); a non-zero runner exit records no failed rows (Design: "records only the files its results show failed") and prints `results not recorded: the run exited N` instead of `runner exited <code>: <n> results not recorded`; a missing results file prints one line, not `FAIL <spec>: results file missing` per spec; `gate-check` prints `reused: an affected gate passed on this content` without `at <time>` (Usability, Whole-gate reuse); `pickman/check.sh`'s usage still reads `[--full|--affected] [--base REF]` (Modules: "`pickman/check.sh`'s usage names `--fresh`"); `select.luau`'s `Context.places` comment still says "empty until c0165 step 2 reads them".
Critique: each is small, but the Design is the contract c0238 to c0240 build on (c0238's waiter reads failed rows).
Consequences: none.
Recommendation: implement each as designed, or record it in the Verification log with its reason; fix the stale comment.

### F6 [low] The new zz-test bullet calls the db "the one writer outside `.cache`", which the next bullet contradicts
Where: `z-nile/skills/zz-test/SKILL.md`, "Specs never touch the real repository"
Evidence: the added bullet reads "**The one writer outside `.cache`** is the gate's results db (…)"; the next bullet's Allowed writers also list `pickman/sourcemap.json` and promote-check's transient copies in `<home>/tests/acceptance/`. The Design places the verbatim phrase "in 'Allowed writers'".
Critique: a rule list that disagrees with itself is read either way.
Consequences: none (AC10 checks the phrase verbatim, which stays).
Recommendation: put the phrase into the Allowed writers sentence as the Design says and drop "The one writer".

### F7 [low] A nested runner in the same home inherits `PICKMAN_RESULTS` and writes the orchestrator's results file
Where: `z-nile/tests/run.luau:195-215`; Design, Runner results ("a nested run inherits the orchestrator's value, naming another home's `.cache`: it writes nothing")
Evidence: `tooling/run-lane-error.spec` runs `lune run tests/run -- --jobs 2 …` with `cwd = root`, the z-nile home itself (`pwd -P`), so `resultsPath()` accepts the inherited path and the nested coordinator writes and merges into it (`grep -rln '"tests/run"' z-nile/tests pickman/tests | grep -c '\.spec\.luau$'` counts 22 specs that start a runner; which of them start it in their own home was not checked one by one). The outer runner writes last, so normally its own record wins; when the outer worker dies after its spec, its part holds the nested run's files, and the orchestrator then finds no result for its spec (fail closed).
Critique: the Design's premise is false; today it only costs a confusing failure.
Consequences: none.
Recommendation: have the runner clear `process.env.PICKMAN_RESULTS` once it has read it (workers already get theirs explicitly), so no spec or nested runner inherits it; an unsequestered case: a spec that runs a nested runner in the same home leaves the outer results naming only the outer file.

### F8 [low] E2, "blocking for `done`", has no record
Where: c0165.md, Unknowns E2; Verification log
Evidence: the Verification log has no E2 line and `z-nile/setup.sh` is unchanged. CI runs no spec today (`.github/workflows/deploy.yml` line 3: the gate is local; only `deploy.yml` exists), so the experiment's premise ("`store.spec` and the `gate-*` specs need it once promoted") does not hold.
Critique: an open blocking experiment at `done` reads as skipped work.
Consequences: none.
Recommendation: record E2 as moot with that evidence (or run it), and say why `setup.sh` is untouched.

## Judged criteria (code mode only)
None: c0165 has no Judged criteria.

Lesson candidate (for the lead to file; a reviewer writes none): zz-arch, "a reader of a tool's JSON never relies on version-specific encoding (SQLite's JSON subtype through a subquery), because R0081's `rows` read an array on sqlite 3.51 and a string on 3.54 and crashed the gate; check: does the query wrap every nested JSON value in `json(...)`, or does one reader decode both forms, and is the call guarded so a failure turns reuse off?"

Verdict: changes
