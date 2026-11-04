# Review 001: c0165 (design mode)
Inputs: 73d664d2 (c0165.md, check.sh, acceptance/*.spec.luau); capture 5fa62e59 (`./zn capture c0165`); `./zn lessons --when design --full`; evidence runs on the prototype clone (ae5bd9d8 + edits, its acceptance files byte-identical to 73d664d2's per `cmp`), in a throwaway repo under the scratchpad, and against the real worktree's `origin/main`.

### F1 [high] The orchestrator ignores the runner's exit status, so a browser-guard or tripwire failure becomes a passing gate and a recorded, reusable pass
Where: Design, "`specs.luau run`" step 3 and 5 ("Exit 0 only when nothing failed", counted from the results file); "Full mode" (`record --full` records "every listed file's result"); Rules and mutants (no row)
Evidence: The runner fails a run *after* every spec has passed and written its record in two places: the browser guard (outer runner, `FAIL a spec started a browser`, exit 1) and the tripwire (`fence.enter()`'s second snapshot, after the jailed run). I ran this on the prototype with a probe spec that calls `open -O x` and passes:
`lune run tests/run -- tests/zzprobe/opener.spec.luau` → `FAIL a spec started a browser …`, `runner exit 1`;
`lune run z-nile/specs -- run --project z-nile -- tests/zzprobe/opener.spec.luau` → `1 passed, 0 failed`, `orchestrator exit 0`; a second run → `reused tests/zzprobe/opener.spec.luau`, exit 0. (Probe and its row removed afterwards.) The prototype's `execute` reads `r.code` nowhere. A tripwire firing (remotes, config, branch or history changed during the run) takes the same path: results written inside the jail, exit 1 outside, the orchestrator says passed. AGENTS.md: "If its tripwire fires, stop and report"; the gate would now print `GATE PASSED (affected)` and store the pass for every later run in every worktree.
Critique: This turns two of the runner's guards into no-ops for every affected gate, and stores the result. The tempting fix, "if the runner exits non-zero, count one extra failure", still records the per-file passes from that run.
Consequences: A run whose exit status is non-zero while its file records show no failure has a failure the records can't attribute. So none of its passes can be trusted. `record --full` has the same hole: check.sh keeps the gate red, but the passes it records serve later affected runs.
Recommendation: In both `run` and `record --full`, record `passed` rows only from a runner invocation that exited 0. A non-zero exit records failures only (or nothing), and when the records show no failure the orchestrator prints `runner exited <code>: <n> results not recorded` and counts the run failed. Add a Rules row and a gate.spec case: a fixture spec that runs the stubbed `open` and passes → `specs run` exits non-zero, no `passed` row exists, the next run runs it again. The same case through `check.sh --full` → no `passed` row. Mutant: exit status ignored.
Lesson: zz-arch/tripwire-covers-every-interval

### F2 [high] The local db's learned edges change what promoted specs see from `z-nile/affected`, inside the jail too
Where: Modules (`affected.luau` "with … the db's learned inputs"; `context.luau` "merges the db's learned inputs when the db file already exists"); Regression guard (claims `c0120/graph-homes`, `tooling/affected` stay green)
Evidence: Promoted specs run the real CLI at the checkout top (`c0120/graph-homes.spec.luau:27,148-158`, `c0114/gate-cover.spec.luau:25`, `c0047/override-check`), so `workspace.dbPath` resolves to the real main checkout's db, which the jail lets them read. On the prototype I added one learned row (`z-nile`, `tests/tooling/affected.spec.luau`, `pickman/src/shared/Logic/Maze/init.luau`), the kind an `unbisected` miss records (every candidate becomes an input, other homes' files included). Then `lune run tests/run -- tests/acceptance/c0120/graph-homes.spec.luau` → `FAIL … graph-homes.spec:157: expected "", got "tests/tooling/affected.spec.luau"`. (Row deleted afterwards.) So a promoted spec goes red on one machine and stays green in CI. Its own fingerprint doesn't include the db, so the red result also disagrees with reused passes. The design's own fixture gates avoid this only because they write a fixture db.
Critique: Machine-local state now decides spec results, which breaks zz-test's "Deterministic" rule. The tempting fix, "skip the db when `PICKMAN_TEST_FENCE` is set", breaks gate.spec's own nested gates, which need their fixture db's learned rows (AC8's `after` call).
Consequences: Whoever reads the db must say so explicitly. Bare `affected` is what reviewers paste into Override checks (zz-review item 4), so its output should be the committed answer.
Recommendation: `z-nile/affected` reads learned rows only with an explicit `--learned` flag. check.sh's selection call and `specs.luau` pass it, and a bare call reads only `inputs.tsv`. Change gate.spec AC8's `after` call to pass `--learned`, and add a case: with a learned row in the fixture db, bare `affected` doesn't print the spec and `--learned` does. Add a Rules row (mutant: learned rows read unconditionally). Update the `affected.luau` row of the Modules table and the zz-test Affected-selection wording to match.
Lesson: zz-test/new-commands-run-in-a-copy

### F3 [high] The capture's "no … spec can forge a pass" is reworded into an "accepted residue" with no user line, and the residue is wider than stated
Where: Design, "Where things run", 4th bullet ("This is the accepted residue, and the user's decision covers it"); capture: "No failed or partial run, different tree or spec can forge a pass."
Evidence: The decision it cites is "The full gate at merge runs all for real so we can find out if dependency graph has gaps". That answers whether the merge gate may reuse passes, not whether a spec may forge one. No `Decided with the user` line covers forgery. The bullet also says a forged file "can only forge a pass in a run that reuses results, never in a full run". But `record --full` reads the same kind of file (`<home>/.cache/spec-results-<check.sh pid>.json`, writable by every spec in that run) and writes `passed` rows from it, which later affected runs reuse (prototype `recordCommand`: `byFile` → `resultsdb.record` for every listed file, whatever the runner's status).
Critique: This is a captured outcome removed without a decision (zz-review item 11). The tempting fix is to add a user line quoting the old decision. That still doesn't match what the user asked.
Consequences: A pass can be made unforgeable without the user: the runner passes something no spec can read into the results. A spec runs in the same Lune process as the code that writes the record, but it can't read that code's locals (Luau has no `debug.getlocal`).
Recommendation: Either (a) keep the outcome: the orchestrator writes a fresh random token to the runner's stdin. The runner (coordinator, and each worker through its stdin) reads it before any spec loads, keeps it only in a local, and writes it into the results file. The orchestrator refuses a file without the token (no rows recorded, every claimed file counted failed). Add a gate.spec case where a fixture spec overwrites the results file with an all-pass record for a broken spec, expecting no `passed` row and a failed run. Combined with F1's exit-0 rule, this closes both sources. Or (b) escalate to the user: keep the residue, naming the exact paths (affected runs and `record --full` rows) and that the pre-merge gates, the reviewer's included, can be fooled. Fix the "never in a full run" sentence either way.
Lesson: zz-arch/guard-state-out-of-reach-or-checked

### F4 [high] The blob map fails open: a failed `git` read leaves a modified file at its index blob id, so a stale pass is reused for new content
Where: Design, "`workspace.luau` (the reads)"; Rules and mutants (no row); prototype `z-nile/lib/workspace.luau` `blobs`
Evidence: In a throwaway repo (scratchpad `blobprobe`), I committed `a.txt` and then edited it. `workspace.blobs` gives `100644 e9d25acc…` (the edited content). With a `git` wrapper that fails `hash-object` it gives `100644 78981922…`, the index's id, which equals `git ls-files -s a.txt`. In other words, the edit doesn't exist for the fingerprint or the digest. Real triggers: a file deleted or renamed between `ls-files -m` and `hash-object` (one missing path fails the whole `--stdin-paths` batch), and a path containing a newline (`-z` lists are rejoined with `\n` for `--stdin-paths`, which misaligns ids and paths). If `ls-files -s` itself fails, the map is empty, and every fingerprint is a function of the spec path and tools alone.
Critique: A read that fails silently becomes "unchanged", which is the defect zz-arch/guard-no-is-explicit names, and it produces exactly the capture's forbidden "different tree … forge a pass". The tempting fix, `if not ok then error`, would crash the gate instead of falling back.
Consequences: Blob failures have to reach the "reuse off" path that `open` failures already take. That makes "reuse off" a fallback for two different causes, and the message should say which one.
Recommendation: `workspace.blobs` returns `nil, reason` when any of its git calls fails, when the id count differs from the path count, or when a path contains a newline. `specs.luau run` then goes to "reuse off: <reason>", `record --full` records nothing, and `digest` prints nothing, so no whole-gate reuse or record happens. Re-reading after the run (R31) follows the same rule. Add a Rules row and a digest.spec case with the failing-`hash-object` wrapper (a stand-in that answers only that subcommand) expecting `nil`, plus a gate.spec case expecting `reuse off` and every spec run.
Lesson: zz-arch/guard-no-is-explicit

### F5 [high] Misses caused by files under a project root can never be declared or learned, and the Design's own `inputs.tsv` example is refused by its parser
Where: Design, `select.luau` "`inputs.tsv` format" (refuses any `.tracker` segment or root path) vs. its "Example" line `tests/acceptance/c0063/narrowed.spec.luau	pickman/.tracker/issues/done/f0031/acceptance/`; "Learning", step 3 ("the candidates are the changed paths outside project roots"); R3
Evidence: The prototype's `parseInputs` (`select.luau:246-253`) returns `the input must not name a project root` for that example, and the real `pickman/tests/acceptance/c0063/narrowed.spec.luau:58` does read `.tracker/issues/done/…/check.sh`. `grep -rlE '\.tracker|tracker/' z-nile/tests pickman/tests --include='*.spec.luau'` lists 138 spec files. When a miss's change is only under a root, `learnMisses` returns at `#candidates == 0` and prints nothing. When the root change is mixed with others, trial (a) doesn't apply it, so the miss reports `not reproduced in a copy`, which is false. Before this change the author's and reviewer's `--full` runs caught these misses before review. Now only `done` does, and it can't learn them.
Critique: The captured outcome "A merge failure teaches the selector … records that dependency" has no Design for this class, and the Solution's "need declared inputs or must always run" can't be followed for it. The tempting fix, deleting the example, leaves the class unlearnable.
Consequences: A root path that is allowed as an input is fine when it's narrow (a done folder, one check.sh). The reason for the root exemption is churn from tracker commits, and `spend.md` is the worst of it. The invariant "a change under a project root never changes a fingerprint" then becomes "only a declared or learned one does", and R3 changes with it.
Recommendation: Let `parseInputs` and `learn` accept a path under a root when it isn't the root itself, isn't a `spend.md`, and has no `..`. Let learning's candidates include changed root paths except `spend.md`, and print `not learned: <spec>: no candidate outside spend.md` instead of returning silently. Restate R3, AC2 and the fingerprint bullets to match. Add cases: parse accepts the example and refuses `pickman/.tracker` and `…/spend.md`, and a gate.spec miss seeded by a tracker-folder file gets learned. If the user wants roots kept out entirely, escalate to the user: offer either that, accepting that this class only fails at `done`, or an "always run" marker in `inputs.tsv` for such specs, with its cost (they never reuse).

### F6 [high] The capture's fingerprint includes "the gate mode"; the Design's fingerprint leaves it out, with no decision line
Where: Design, `fingerprint.luau` (`of`'s lines: version, spec path, tools, inputs, entries); capture's "Fingerprint per spec" bullet
Evidence: The capture says the fingerprint is made of "… the shared runner and harness, the tool versions and the gate mode". `of` has no mode line. `record --full` writes rows that affected runs then reuse (the AC7 case shows a full gate writing rows), so a full-mode pass serves an affected run. No `Scope decision` or `Decided with the user` line covers this.
Critique: This is an element of a captured outcome dropped silently (item 11). The Design may well have a good reason (full mode never reads rows), but it has to say so and the user has to agree to it.
Consequences: Adding the mode means full-mode rows serve no affected run, so `record --full`'s per-spec writes become a case log only. Leaving it out means `run` and `record --full` must behave identically per spec file (same env, same runner path), which F1 shows they don't today in what they record.
Recommendation: Add the line `mode <affected|full>` to `of` (and an AC2 case where the same content under the other mode gives a different fingerprint). Alternatively, ask the user and record `Decided with the user (date): fingerprints are mode-free because full never reads rows`.
Lesson: z-design/never-narrow-captured-scope

### F7 [medium] "Gate speed from `./zn done`'s full gate" can't be recorded without editing tracked files after `done`, which also breaks `--full --reuse`
Where: Wording (zz-execute Phase 3 step 3, ``from `./zn done`'s full gate``); Gate modes table (merge condition reuses `done`'s run); digest exclusions (only `spend.md`)
Evidence: The speed goes in "each issue's Verification log" (issue docs under the root). zz-execute Phase 5 step 1 writes the final Verification log *before* `done`, and step 2 says "so … nothing needs changing after it". To record done's speed, the lead must edit issue docs after `done`. Those aren't `spend.md`, so the digest changes, the merge condition's `--full --reuse` finds no row and runs a full gate again, and a new commit lands after `done`.
Critique: The restated rule contradicts the protocol it sits in and defeats Scope decision 4.
Consequences: Either the speed comes from a run before `done`, which is now affected, so it's not a full-gate speed, or `done` records it itself.
Recommendation: Pick one and pin it in AC10. (a) `./zn done` writes the gate's `gate wall time` and `slowest:` line into a file the digest already excludes (the raft's `spend.md`, which `done` writes after the gate anyway), and Phase 3 step 3 says to read it there. Or (b) Phase 3 step 3 records the speed from a named full run before `done` (Phase 3 step 2 is now `--affected`, so add an explicit `z-nile/check.sh --full` there), accepting one extra full run. Either way, add a gate-level case or a docs pin showing that nothing in the protocol edits a non-`spend.md` tracker file between `done` and the merge condition.

### F8 [medium] No case exercises the path Scope decision 4 rests on: a full gate on `done`'s uncommitted tree reused on the committed final head
Where: Test plan AC7; gate.spec "AC7 … --full --reuse" (only `commit --allow-empty` on a clean tree)
Evidence: `./zn done` (z-nile/engine/main.luau `cmd.done`) runs `z-nile/check.sh --full` on a tree with staged `git mv` renames and staged check.sh rewrites. `recordAndCommit` then runs `git add -A` and writes `spend.md` (`spend.appendRow`, `spend.writeRaft`) before committing. The only reuse-after-commit case commits nothing. A digest that read HEAD's tree for tracked files, or that missed staged renames, would pass every case.
Critique: Without this case the implementer can't tell that the merge condition still runs a full gate every time, which is the whole saving of decision 4.
Consequences: none beyond the case.
Recommendation: Add a gate.spec case: stage a rename and an edit, run `check.sh --full`, write a `pickman/.tracker/…/spend.md`, commit everything, then expect `check.sh --full --reuse` to print `reused: a full gate passed on this content` and the specs not to have run. Also add the negative: the same, plus an edit of a non-spend tracker doc, runs again.
Lesson: z-design/spec-design-correspondence

### F9 [medium] zz-test's "Exit criteria" still says RC0 runs `--full`, a restated rule missing from the Wording list
Where: Restated rules / Wording (zz-test entries); `z-nile/skills/zz-test/SKILL.md:60` (prototype `:63`)
Evidence: `grep -n 'Exit criteria' <proto>/z-nile/skills/zz-test/SKILL.md` → "a raft's `check.sh` runs its project's gate (`"$ZN_ROOT/z-nile/check.sh" --project <project> --full`)", while the prototype's template RC0 says `--affected`. The Design's list for zz-test is "table, Affected selection, Graph miss, Allowed writers". Also, AGENTS.md's new text (prototype line 5) lists the db among the files "`./zn` itself" writes, but the writer is the gate (`z-nile/specs`, from any worktree, including a raft check.sh's RC0), not `./zn`.
Critique: Two restatements now disagree with the rule.
Consequences: none.
Recommendation: Add the Exit-criteria sentence (with `--affected`) to the Wording list and to docs.spec. Reword the AGENTS.md sentence to name the gate as a writer of the main checkout (``…; and the gate writes its results db, `.claude/.znile_tests.sqlite` ``), and pin that wording.
Lesson: z-design/restated-rules-move-together

### F10 [medium] AC12 maps every `--affected` back to `--full`, so a changed non-RC0 pin in an Override passes, and its premise comment is false
Where: check.sh `overrides_narrowed` (comment: "none of the four says "affected" on main")
Evidence: `git show origin/main:z-nile/tests/acceptance/c0120/docs.spec.luau | grep -n affected` → `114: … z-nile/affected …`, and c0114/docs.spec has `65: "scripts/affected"`. The sed doesn't touch those, but it reverts *any* `--affected`: c0120/docs.spec line 93 pins ``| `pickman/check.sh [--full]` …``. Changing that to `[--affected]` (or line 460 of homes.spec, which isn't an RC0 line) still passes AC12, and AC11 allows the file.
Critique: The changeable part needs a strict positive boundary. The tempting fix, also grepping for `RC0`, doesn't cover homes.spec:460, which has no `RC0` text.
Consequences: none.
Recommendation: Apply the reverse substitution only on lines matching the template's RC0 call, `z-nile/check.sh" --project [^ ]+ --affected` (sed address), and keep the byte-for-byte compare of everything else. Fix the comment.
Lesson: zz-test/split-checks-share-one-boundary

### F11 [medium] Several stated behaviours have no case and no Rules row
Where: Rules and mutants; Test plan
Evidence: Searched gate.spec, store.spec and plan.spec for each of these:
- the wait loop on a row that becomes `failed` ("counts as a failure and prints its stored detail"): every concurrent case uses passing specs, so a mutant that tallies a waited `failed` row as passed survives;
- `gate-record`'s second digest ("A tree that changed during the gate records nothing"): R31 names "digest (full)", but its case (`changed`) calls `specs run`, not `check.sh`;
- `record --full`'s `--digest` mismatch ("records nothing and says so");
- "a claimed file the results don't list … is released and counted failed".
Critique: Each is a branch that a plausible mutant deletes without any case going red.
Consequences: none.
Recommendation: Add rows and cases: two concurrent runs of a slow failing spec (both exit non-zero, one ran it, the waiter prints `failed in pid`); a check.sh gate whose fixture spec edits a tracked file, leaving no `gates` row, so the next identical gate runs; the same through `--full`, leaving no `passed` rows; and a runner stub that writes no results, after which the row is absent and the run fails.
Lesson: zz-test/seed-every-enumerated-case

### F12 [medium] A takeover doesn't consider the dead owner's still-running runner, which holds the home's lock
Where: Design, `reuseplan.decide` (take over on a dead owner) and run step 4; zz-test Lock ("waits up to `PICKMAN_TEST_LOCK_WAIT` … default 240")
Evidence: The owner is the orchestrator's pid. When only it dies (`kill <pid>`, a crash in the orchestrator itself), its `lune run tests/run` child keeps running and holds `<home>/.cache/tests-run.lock`. A waiter in the same worktree takes the row over at once, and its runner then waits up to 240 s for the lock and fails, so the spec counts failed. The orphan also leaves `spec-results-<dead pid>.json` behind.
Critique: The capture's crash detection promises the waiter "runs the spec itself". The Design never says what happens to the owner's child (zz-arch/children-need-a-lifeline).
Consequences: Treating the runner's pid as part of the owner would need the owner record to change shape.
Recommendation: State and implement one rule: either the orchestrator runs the runner in its own process group and kills it on exit (as far as Lune allows; say what's left), or `holds` also asks the home's lock (a live runner pid recorded for that owner keeps the row held). Sweep `spec-results-*.json` files whose owner is dead. Add a case that kills only the orchestrator.
Lesson: zz-arch/children-need-a-lifeline

### F13 [medium] Learning has a cap per miss but none in total, inside `done`, `land` and CI
Where: Design, "Learning a missed dependency" step 3 (`PICKMAN_LEARN_MAX` per miss); Scalability ("capped at 16 one-spec trials per miss")
Evidence: For each miss the plan runs up to 2 + 16 trials, each a fresh jailed `tests/run` in the clone. A change to one data file that 30 specs read through no require edge gives 30 misses and up to 540 trials, all before `done` reports its failure (and `done`'s rollback waits for them).
Critique: A failing gate can get slower by an unbounded amount.
Consequences: Once there is a total cap, some misses go untried, and they need a printed line.
Recommendation: Add a total trial budget (for example `PICKMAN_LEARN_MAX` total and per miss, or a wall-time budget). Print `not learned: <spec>: learning budget spent` for the rest, and add a plan.spec case for it.

### F14 [low] The `isInput` definition reads as a contradiction
Where: Design, `select.luau`, "`isInput(ctx, S, p)` holds when all of these are true:" followed by items that start with "or"
Evidence: As written it requires every item, place libraries and inputs.tsv included, at once.
Recommendation: "holds when `p` is not under a project root and at least one of these holds: …".

### F15 [low] "A change alters a spec's fingerprint exactly when it makes the selector pick that spec" isn't true for a removed `inputs.tsv` line
Where: `fingerprint.luau` "these hold" bullets; AC1
Evidence: Removing S's line changes S's fingerprint (its entry lines change, and the old `inputs.tsv` blob was an input), but `isInput(newCtx, S, "…/inputs.tsv")` is false because the new file no longer names S, so the selector doesn't pick S. The only effect is a harmless rerun, but the Design states it as an invariant that AC1 pins.
Recommendation: State the exception, or evaluate `inputs.tsv` membership against the old and new files both.

### F16 [low] A whole-gate reuse hides the lint summary that zz-execute Phase 4 step 1 says to read
Where: Whole-gate reuse (prints only `reused: …` and `GATE PASSED`); Wording, Phase 4 step 1 ("…`--affected` and read the whole lint summary")
Evidence: A reused gate runs no static stage, so it prints no `warnings` lines.
Recommendation: Store the static stages' summary lines with the `gates` row and print them on reuse, or change the Phase 4 wording to say that a reused gate has none to read.

Verdict: changes
