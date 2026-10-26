# Review 002: c0154 (design mode)
Inputs: prep `prep-gate-slow` bf60e3ad (c0154.md, check.sh, acceptance/{schedule.spec,durations}.luau, experiments/{schedule.luau,run.patch}, design-review-001, design-refute-001, harvest.md); `./zn lessons --when design`; zz-review lessons. The prototype (run.patch + schedule.luau, the spec promoted to `tests/acceptance/c0154`) is applied in a scratch clone of bf60e3ad (scratchpad `dr-c0154-002/clone`).
Dropped from design-review-001: F1, F2, F3, F4, F5, F6, F7

Rulings on refute 001:
- F1 (positions): right. `schedule.order` returns positions and the runner writes `outcomes[position]`; "a file listed twice" passes on the prototype (`2 passed, 0 failed, 2 spec files`).
- F2 (clock dependence): right, and measured this round. The spec ran 5/5 green under 36 busy loops (load 39 to 76), then 5/5 under 24 busy loops plus 16 process-spawn loops (load 68 to 94), using a copy of the spec that prints each run's start offsets. The first two files started 0 to 19 ms apart. The third started 3078 to 3160 ms after the first. So start-up jitter at load 94 is tens of milliseconds against a 3 s hold, and the only clock reading left ("which two started first") has about 3 s of slack.
- F3 (no seed): right. The main checkout never runs a gate, so there is nothing to seed from. Item 4 says plainly that each worktree's first full gate runs in path order.
- F4 (JC1): right. JC1 is now a computation on a recorded run, and the user's "Drop 200 s" removes the live target.
- F5 (atomic write, written only with the home's files, gone files dropped): right for the write. Measured: with lune 0.10.5 (rokit.toml) and 0.11.1, `fs.move(tmp, rec, true)` repeated 3000 times against two concurrent readers gave 0 missing and 0 torn reads out of ~22,000. The control, an in-place `fs.writeFile`, gave 531 torn reads out of 3471. The "written only with the home's files" rule is not pinned by its case: see F2 below.
- F6 (tie-break mutants): right. M4b, re-run here, turns "orders unrecorded files first…" red.
- F7: right.

Checked and holding:
- **Concurrent gates on one worktree's record.** Two concurrent writers can't happen at the top level. `fence.enter` takes `<home>/.cache/tests-run.lock` (`takeLock`, fence.luau:288) before the jailed child, and the coordinator runs and writes the record inside that child. So a second top-level run in the same home (a gate, a `./zn check`, a check.sh's multi-file run) waits for the first to finish or gives up. pickman and z-nile have different homes, so different locks and different records. Nested runners write the record only for `tests/…` paths relative to their own cwd. Every nested concurrent run in the corpus names `.cache/…` files in this home, or runs in a fixture home under `.cache` (search: `git grep -nE '"tests/run"' -- '*.luau'`; the hits are c0049 `.cache/c0470-runner/*`, run-lane-error `.cache/run-lane-error/*`, and the c0058/c0127/c0114/fence-*/lock-start-ids fixtures under `.cache`; c0034, c0059, c0114 classified and the engine run one file, in-process). Every nested run also finishes before the outer coordinator writes. So at worst, a lost update loses only a nested run's own lines, and only ordering depends on the record.
- **"Only when the run includes the home's own specs" is well defined.** The home is the runner's cwd: the runner refuses any other cwd, and `DURATIONS` is relative to it. The test is "an outcome whose path, after the runner strips the cwd prefix, starts `tests/`". In-process runs (`--jobs 1`, one file) never reach the coordinator. A fixture home under `.cache` writes its own `.cache` record, inside the jail's writable area.
- **Repository safety.** The record and its temp file are in `<home>/.cache`, which is gitignored (`git check-ignore`: `.gitignore:2:.cache/` for both homes) and the only place the jail lets the run write. `rename` replaces a symlink planted at the record path instead of following it. `math.random` is seeded per process (three runs gave three different first values), so temp names don't collide. The runner case's fixture lives under `.cache/c0154-runner` with no repository of its own, and its nested runner is guarded by the inherited marker (`guarded`: `marker/.cache/` prefix), so it adds no lock and no jail. Nothing in check.sh writes anything.
- **Copies of the runner in fixtures.** Every fixture spec that copies `z-nile/tests/run.luau` copies the whole `z-nile/tests/lib` (fence-cache-entry copies it separately), so the new `require("./lib/schedule")` resolves in each (search: `grep -rlF run.luau z-nile/tests`, then the copy lists of the 11 hits).

### F1 [high] c0154's own check.sh turns every full gate red: c0120's check-paths spec rejects AC5's `pickman/tests/acceptance`
Where: check.sh `promoted_unchanged` (`-- 'pickman/tests/acceptance' 'z-nile/tests/acceptance'`); promoted spec `z-nile/tests/acceptance/c0120/check-paths.spec.luau`.
Evidence: on a scratch clone of bf60e3ad, with nothing changed, `lune run tests/run -- --jobs 2 tests/acceptance/c0120/check-paths.spec.luau tests/acceptance/c0116/promote.spec.luau` from `z-nile/` gives `FAIL tests/acceptance/c0120/check-paths.spec.luau :: every unfinished item's check.sh, in every project root, names only paths that exist from its home` with `got "z-nile/.tracker/issues/c0154/check.sh: pickman/tests/acceptance (from z-nile)"`, and `6 passed, 1 failed`. The z-nile full run on the prototype fails the same case. That spec reads every unfinished item's check.sh, so the prep PR's own gate is red, and so is every gate on main after it lands, until c0154 is done.
Critique: the path is valid for `git -C "$ZN_ROOT"`, but the scanner reads literal paths from the home. The tempting fix is an exemption in check-paths.spec, which would mean editing a promoted spec and weakening a guard.
Consequences: none if the path stops being a literal.
Recommendation: name the paths through the root, as `"$ZN_ROOT/pickman/tests/acceptance" "$ZN_ROOT/z-nile/tests/acceptance"` (a word with `$` is not a literal path to the scanner, and git accepts an absolute pathspec inside the work tree), and the grep filter to match. Re-run check-paths.spec and `AC_LIST=1` on the prep, and record that in the Verification log. Run the whole gate on the prep commit before the next round (F3).
Lesson: z-design/rerun-skipped-checks-after-edits

### F2 [high] the sequestered spec doesn't type-check: line 240 passes `string.find`'s two results to `t.expect`
Where: acceptance/schedule.spec.luau:240, `t.expect(string.find(fs.readFile(RECORD), "gone.spec", 1, true)).toBe(nil)`, added in round 001.
Evidence: on the prototype with the spec promoted, the z-nile full run fails `tests/acceptance/c0116/promote.spec.luau :: copies the issue's one spec, checks it, and removes the copy` with `z-nile/tests/acceptance/c0154/schedule.spec.luau(240,13): TypeError: Argument count mismatch. Function 't.expect' expects 0 to 1 argument, but 2 are specified`. `./zn promote-check c0154` on bare bf60e3ad reports the same error at (240,13), besides the expected "unknown module" errors from the module that doesn't exist yet. E3 records this exact mistake (a multi-return in t.expect) as fixed once already. The round-001 edit brought it back, and nothing re-ran the type check.
Critique: at `done` the promotion check and the gate's types stage both fail on a sequestered file the executor may not edit. That is an escalation in the middle of execution.
Consequences: none.
Recommendation: wrap it as `(string.find(…))`, as the file does elsewhere. Then run `./zn promote-check c0154` against the prototype (types, lint, format) and record it.
Lesson: z-design/rerun-skipped-checks-after-edits

### F3 [medium] the round-001 changes were never run on Linux or through the full gate, and the lesson asks for both
Where: Verification log, last bullet ("schedule.spec 8/8 five times … mutants … all killed"). E3 ("the full gate on the prototype … is in the Verification log"). Regression guard ("Specs that assumed concurrency or order between files would show up in the prototype's full run (E3)").
Evidence: the only full-gate run recorded is the first prototype's, before round 001 changed the coordinator (positions, the `any` guard, `keep`, temp and rename). `grep -rniE "linux|ci-verify" z-nile/.tracker/issues/c0154/` finds only G2's "CI keeps path order". Yet schedule.spec is promoted into every gate, CI's Linux one included, where it spawns nested runners on a small runner under the Linux jail (c0075). The runner case is the part most likely to differ there: `cp -R`, `pwd -P`, guarded nested runs, 3 s holds on 2 vCPUs. The one full run since then is mine (Verification by the reviewer, below), and it found F1 and F2. I can't run CI, because a reviewer may not push.
Critique: lesson z-design/prove-specs-pass-on-a-prototype: "has each platform the specs run on (macOS in the jail, Linux in CI, which `z-nile/ci-verify.sh` reaches from a throwaway branch) run them on the prototype … with the specs, mutants and gate re-run after any change there?" The tempting fix is "Linux is execution's problem". That is the defect the lesson records.
Consequences: a Linux failure would mean changing the runner case, which is sequestered. That is cheap now and costly after ready.
Recommendation: run `z-nile/ci-verify.sh` on a throwaway branch carrying the prototype with the spec promoted. Run the full gate per project (`z-nile/check.sh --full`) on the round-002 prototype. Record both in the Verification log.
Lesson: z-design/prove-specs-pass-on-a-prototype

### F4 [low] "nothing written without the home's files" survives its mutant; an empty merge writes "\n", which reads as an empty record, not no record
Where: Rules row "only the home's tests/ recorded, and nothing written without them". Case "a run naming only a fixture's files leaves the record byte for byte". `schedule.parse` and `render`. Design 2 ("only when the run had any").
Evidence: on the prototype, replacing `if any then` with `if true then` in run.luau leaves schedule.spec at `8 passed, 0 failed`. The case's record was itself written by `render`, so re-rendering it unchanged gives the same bytes. And `schedule.parse("\n")` returns `{ }` (run here), while `render({}, {})` writes `"\n"`. So the mutant, in a home with no record, creates a record that parse accepts as empty. That breaks the Design's "an empty text … makes the whole record nil" and M15's rule, though it schedules exactly as no record does.
Critique: lesson z-design/spec-design-correspondence (a Design rule whose case can't fail without it). M15's case asserts a nil/empty distinction that `order` never sees.
Consequences: none beyond the spec, since ordering is the same either way.
Recommendation: before the fixture-only run, write a non-canonical record by hand (`"1\ttests/a.spec.luau\n"`; a re-render would write `1.00`), and list the mutant "write whenever the run ends" as run. Make `parse` return nil for a text with no lines (`"\n"`, whitespace), not only for `""`, with an assertion.

### F5 [low] the record's parser keeps the last of two lines for one path
Where: `schedule.parse` (`out[path :: string] = n`).
Evidence: from the code: `"1.00\ta\n9.00\ta\n"` parses to `{a = 9}`. `render` never writes such a text. A hand edit or a merge of two records would, and the Design's own rule is that a doubtful record is refused whole.
Recommendation: a repeated path makes `parse` return nil, with one assertion beside the malformed-record ones.
Lesson: zz-arch/parsers-refuse-ambiguity

### F6 [low] check.sh's AC2 and AC4 labels still say round 001's criteria
Where: check.sh AC2 and AC4 against c0154.md's Checked AC2 and AC4.
Evidence: `AC_LIST=1 bash check.sh` prints AC2 as "…merged across runs, and a malformed record is refused whole and replaced". The doc's AC2 adds "rewritten only when a run had the home's own files, cleaned of gone files on a full run, … malformed or empty". AC4's label lacks "with unchanged counts and exit code, a file listed twice included".
Recommendation: copy each AC's current text into its `check` label in prep, since check.sh is sequestered after ready.
Lesson: z-design/spec-design-correspondence

Verification by the reviewer: z-nile's full spec stage (`lune run tests/run` from `z-nile/`) on the prototype with the spec promoted, at load 13 to 31: `1228 passed, 2 failed, 178 spec files` in 384 s. The two failures are F1 and F2. The record afterwards held 178 lines (177 + c0154's spec), and `slowest:` gave claims.spec at 161.4 s, finished.spec at 132.5 s and c0072 land.spec at 93.6 s. pickman's stage and CI were not run.

Candidate lessons (for the lead):
- zz-test: "A case that a file is left byte for byte unchanged starts from bytes the writer would not produce itself (a hand-written, non-canonical text), because a writer that re-renders a canonical file passes it (c0154: the 'write only with the home's files' guard survived); check: would rewriting this file with the code's own renderer change a single byte?"

Verdict: changes
