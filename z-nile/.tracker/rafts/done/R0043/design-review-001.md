# Review 001: R0043 (design mode)
Inputs: prep worktree at 095b177: `tracker/rafts/R0043/{R0043.md,check.sh}`, `tracker/issues/c0114/{c0114.md,check.sh,acceptance/*}`; `scripts/tracker.sh capture c0114`; `scripts/tracker.sh lessons --when design --full`; the programme review `scratchpad/programme-review/c0114.md`; the prototype `.worktree/proto-c0114` (5b6f444), where I re-ran `z-nile/check.sh --full` (GATE PASSED, 72.4 s) and `bash z-nile/.tracker/issues/c0114/check.sh` (12/12). The prototype's sequestered specs and `check.sh` are byte-identical to the prep's. The Overrides list (55 files) matches the prototype's changed promoted specs exactly.

Scope fidelity (item 11): the capture is unmarked. Title, Problem and Solution are verbatim. Each outcome the decided lines move out has its own line: skills go to c0115, `.tracker/` replaces `tracker/`, and `./zn` with a forwarder replaces "goes away". Every remaining outcome has a Checked criterion. No scope finding.
Programme review: F1 to F10 and E1 to E10 are each answered (§ "Programme review of c0114"), with one gap. F2 asked that every guard lookup fail closed, and F1 below shows that one lookup still fails open.

### F1 [high] `guarded()` fails closed only when `fence.sh` is missing; any other failure of the lookup reads as "not guarded", and the tracker publishes from inside a check run
Where: c0114 §7, third bullet; prototype `z-nile/engine/main.luau:207-225`
Evidence: the lookup is `[ -f z-nile/lib/fence.sh ] || exit 3; source z-nile/lib/fence.sh && pickman_guarded "$PWD"`, with `guardedRun = r.ok or r.code == 3`. Every other exit code means "no check is running, publish". That includes 2 (a `fence.sh` that fails to source), 127 (`pickman_guarded` undefined, for example after the programme renames the `pickman_*` functions or a branch breaks `fence.sh`) and a failed `bash`. `pickman_guarded` itself answers "not guarded" with the same `return 1` it uses for "could not tell". This is the fail-open path that programme review F2 named. The user's decision is "Every guard lookup fails closed". The design closes only the missing-file case, and AC7's case only deletes the file.
Critique: the tempting fix is to add more `exit 3` cases (a source failure, a missing function). That again enumerates the failures; it does not make "no" explicit.
Consequences: if "not guarded" becomes a distinct answer, every caller of `pickman_guarded` has to read that answer. The publisher is the only caller today. Fixtures that copy a stub `fence.sh` stop publishing to their fixture origins, unless the stub prints the answer.
Recommendation: make "not guarded" one explicit answer, for example `pickman_guarded` exits 0 when guarded and prints `unguarded` when not. `guarded()` publishes only on exit 0 with exactly that output, and every other outcome counts as guarded, with a "not publishing: cannot ask fence.sh whether a check runs (<reason>)" message. Add guards.spec cases for a `fence.sh` with a syntax error and for one without `pickman_guarded`: both print "not publishing" and leave origin unchanged. Add a Rules row with the mutant `r.ok or r.code == 3`.

### F2 [medium] The stop hook in the main checkout now runs `z-nile/check.sh`, which every pre-c0114 worktree lacks, so a session in an older raft's worktree is blocked at every stop
Where: c0114 §8 bullet 6; prototype `scripts/hooks/stop.sh`; `.claude/settings.json` (the hook runs from `$CLAUDE_PROJECT_DIR`, the main checkout)
Evidence: the hook `cd`s to the session's tree ("gate the tree the session is in") and runs `z-nile/check.sh --affected`. Take R0034, active, or any branch cut before c0114 that edits `src/` or `tests/`. Its tree has no `z-nile/check.sh`, so the hook prints "z-nile/check.sh --affected failed" and exits 2. The session is blocked until its branch merges `origin/main`. Neither §11 ("Old engines and work in flight") nor any spec covers it.
Critique: the hook is the one tooling path where the main checkout's new code runs against an old tree. The tempting fix is to tell agents to merge main first, but that is an instruction an active raft may be unable to follow mid-stream.
Consequences: whichever gate path the hook chooses must exist in both kinds of tree until the forwarders are removed. When they are removed, the removal raft has to switch the hook as well.
Recommendation: the hook runs `scripts/check.sh --affected`, which exists in both trees: the real gate before c0114, the forwarder after. It then switches to `z-nile/check.sh` in the forwarder-removal raft, and §3's removal list names `scripts/hooks/stop.sh`. Alternatively the hook picks whichever of the two exists. Update the gate-cover case to match, and add a case that runs the hook in a fixture tree without `z-nile/` that has a changed `src/` file and a `scripts/check.sh` stub: exit 0 when the stub passes.
Lesson: ticket-prep/new-rules-migrate-existing-work

### F3 [medium] Design rules with no spec case or Rules row: emergent-issue placement, the offline `new raft` rule, and audit's `error registry` and `error old-counter`
Where: c0114 §4 rows `new issue`, `new raft` and `audit`; §5 ("`audit` reports `error old-counter` if it ever parses"); Rules and mutants
Evidence: no acceptance spec, and no spec in `tests/`, mentions `--raft` with a project, `old-counter` or `error registry`; I grepped both the prep and the prototype. The prototype implements the rules (`main.luau:757-765`). Plausible mutants survive the gate:
- an emergent issue filed in the first project instead of beside its raft;
- `--project` naming another project accepted for an emergent issue;
- the offline `new raft` that skips the one-project check;
- `audit` that never reports a bad registry, or a parsing `tracker/next`.

The last one matters most: the tombstone's only after-the-fact alarm is `old-counter`. An old engine's `compact` on a branch could write a valid `tracker/next` (`publish.allowed` refuses it only in new engines). AC12 runs `./zn audit` on the clean real tree, so it can't fail for a missing check. R0043's own emergent issues will be filed by the new engine while the raft sits in `z-nile/.tracker/`.
Recommendation: add roots-cli cases:
- `new issue c x --raft R0010` (a z-nile raft) is filed under `z-nile/.tracker/`, and adding `--project pickman` is refused with the §4 message;
- an offline `new raft` (`PICKMAN_PUBLISH=0`) over members in two roots is refused.

Add audit cases in a fixture: a registry that does not parse gives `error registry`, and a `tracker/next` in counter format gives `error old-counter`. Each gets a Rules row with its mutant.
Lesson: ticket-prep/spec-design-correspondence

### F4 [medium] JC1's rubric fails the prototype, the intended implementation
Where: c0114 Judged JC1
Evidence: the rubric asks `git diff -M -C --find-copies-harder --stat origin/main...HEAD` to show every moved file as `R`/`C` "at least 90% for engine files", and fails "when a moved file shows as a delete and an add". On the prototype that diff shows:
- `z-nile/engine/claims.luau` and `paths.luau` as `A` (a delete and an add);
- `store.luau` C071, `compact.luau` C073, `audit.luau` C077, `trail.luau` C078, `publish.luau` and `history.luau` C080, `main.luau` R089;
- `z-nile/check.sh` C071, `affected.luau` C069;
- `fence.sh` R087 and the hook stubs R079.

The whole-PR diff mixes the move with the edits, so similarity measures the edit size, not reviewability. The reviewer must then either fail a correct PR or bend the rubric.
Recommendation: judge the similarity on the moves-only commit (Implementation step 2), for example `git show -M --find-renames=100% --stat <moves commit>`: every moved file appears there as `R100`, with no edits mixed in. Judge the whole diff only on "each later commit is either a forwarder or shim, or an edit of an already-moved file". Name the commit the reviewer reads (the step 2 commit, by its subject).

### F5 [medium] The second root move is not "one `root` edit plus one `retired` entry": the gate hard-codes `z-nile/.tracker` in seven places and nothing turns red when c0120 adds `pickman/.tracker`
Where: c0114 §8, §12 c0120 bullet, Maintainability ("Nothing in the engine names a root but…")
Evidence: the root names are hard-coded outside the engine in:
- `LUAU_DIRS` (stylua skips hidden folders unless they are named, E9);
- the `affected` exemption `^z%-nile/%.tracker/`;
- the stop hook's `grep -v '^z-nile/\.tracker/'`;
- CI `paths-ignore`;
- `cachepaths.SKIP`;
- repo-fence's per-root `check.sh` scan;
- the sequestration globs.

When c0120 moves pickman to `pickman/.tracker/`:
- pickman's sequestered specs drop out of the format stage;
- a pickman document change selects a full run (`^pickman/` will be code);
- every tracker publish for pickman starts CI.

§12 lists none of these sites. gate-cover pins the literal `z-nile/.tracker`, so no spec ties them to the registry.
Recommendation: derive what can be derived from the registry: `z-nile/check.sh` and `affected.luau` read `projects.toml`'s roots, and `cachepaths`/repo-fence take the roots from `projects.roots`. For the files that can't read it (CI yaml, the stop hook), add a gate-cover case: "every root of `z-nile/projects.toml` (current, not legacy `tracker`) appears in `LUAU_DIRS`, in check.yml's `paths-ignore`, in `cachepaths.SKIP`, in the stop hook's exclusion and in the repo-fence scan". c0120's one registry edit then turns that case red until each site follows. List the sites in §12's c0120 bullet and correct the Maintainability sentence.

### F6 [medium] classified.spec runs every unfinished item's real `check.sh` in the real checkout on every full gate, without first proving that list mode holds
Where: `acceptance/classified.spec.luau`, case "every unfinished item's check.sh still lists…"; precedent `tests/acceptance/c0034/locator.spec.luau:21-23`
Evidence: the case runs `bash <item>/check.sh` with `AC_LIST=1` for every item not in `done/`, in the real tree, across both roots. After promotion it does so for every future item, including drafts whose `check.sh` the tracker publishes straight to `origin/main` without a PR. Lines outside `check` run for real: today, `members`/`find` calls and c0083's top-level `lune run tests/run` (refused only because the runner honours `AC_LIST`). c0034's locator does the same over done items, but it refuses to start unless its first case proved that `ac.sh` honours `AC_LIST`: "a check.sh that ignored AC_LIST would run the whole gate recursively". classified.spec has no such guard. An `ac.sh` (or forwarder) that drops `AC_LIST` would make one spec run every raft's RC0 (`scripts/check.sh --full`) and every acceptance check in the real checkout, and unjailed on Linux CI.
Recommendation: keep the outcome (AC10 checks that live items list through the forwarders) and guard it as c0034 does. First run a fixture `check.sh` through the real `scripts/lib/ac.sh` forwarder with `AC_LIST=1` and a `touch` check, and assert the marker was not written. Make the real-item loop refuse to start (fail, not skip) if that proof failed. Also run each listed `check.sh` with a timeout. Add the mutant "ac.sh ignores AC_LIST" to the Rules table, killed by the proof case.
Lesson: testing/no-vacuous-pass (the loop also passes with `checked >= 10` even if half the items are skipped as drafts; consider pinning the expected set of non-draft items)

### F7 [low] The jail waiver trusts an inherited environment variable
Where: c0114 §7 bullet 4 (Guess 6); prototype `z-nile/lib/fence.sh:57`
Evidence: the missing-hooks refusal is skipped whenever `PICKMAN_TEST_JAIL=sandbox-exec` is in the environment, and the hooks path then points at a folder that doesn't exist. Only `tests/lib/fence.luau` sets the variable, after it has jailed the run, and children inherit both the variable and the jail. So the guess is reasonable and consistent with the decision in practice. guards.spec itself passes the variable to one fixture call. A hand-set or leaked variable in an unjailed shell would silently run a `check.sh` without ref guards.
Recommendation: also require `PICKMAN_FENCE_SPECS=1` together with a valid `PICKMAN_TEST_FENCE` for this checkout's parent run (both set only by the runner's jailed path), and say in §7 that the waiver rests on the runner's marker. The user confirms Guess 6 as written or with this narrowing.

### F8 [low] Stale and inconsistent text
Where: various
Evidence:
- c0114 §Design says "`prototype.patch` beside this document", but no such file is in `tracker/issues/c0114/`, and branch `proto-c0114` is not on origin. An executor on another machine has only the documents (lesson ticket-prep/specify-every-named-artifact).
- The spec header comments use an old AC numbering: guards.spec "AC15", classified "AC18, AC20", publish-roots "AC6, AC8", roots-cli "AC4-AC7". The document has AC1 to AC12.
- R0043 Theme dates the guesses "2026-10-21", a day after the prep date.
- c0114 Non-goals still say "The game stays at the repo root until a later game is nested", which the 2026-10-20 scope decision supersedes. Mark it superseded inline.
- The architecture skill line 34 still lists the aliases as `@logic, @shared, @tests, @scripts` "only for `tests/` and `scripts/`", and `@znile` and `z-nile/` are missing (lesson ticket-prep/restated-rules-move-together).
- The new tracker-skill sentence "A raft … never spans two" contradicts R0001 (Guess 7). Add "(R0001, from before c0114, is the one exception)".
- R0043's Risks & rollback does not name the lessons that changed the design (ticket-prep step 1 of the review stage).

Recommendation: fix each one. Either commit `prototype.patch`, or push `proto-c0114` and name it, or delete the sentence.

### F9 [low] Two gate-cover cases pin exact command text the Design doesn't state
Where: gate-cover "the stop hook gates…" (`grep -E '^(src|tests|z-nile)/'`, `grep -v '^z-nile/\.tracker/'`) and "the types stage…" (`--platform=standard --ignore='**/.tracker/**' tests scripts z-nile`)
Evidence: §8 states the behaviour, not the spelling. A correct hook that writes `grep -Ev` or orders the folders differently fails a sequestered spec the executor may not edit (lesson ticket-prep/spec-design-correspondence). If F2 is taken, the hook case changes anyway.
Recommendation: test behaviour. Run the hook in a fixture with a changed `z-nile/engine/x.luau` and a stub gate that records its call, then with only a `z-nile/.tracker/` change, and expect no call. Alternatively, quote the exact lines in §8 so that the Design states them.

Lesson candidates (for the lead):
- architecture: a guard's "no" is one explicit answer, and every other outcome of the lookup (missing file, source error, missing function, crash) counts as "guarded". Why: F1, where `guarded()` closed only the missing-file case. Check: "Which outcomes of this guard lookup lead to the unguarded action, and is each one an explicit 'no'?"
- tracker: a hook or tool that runs from the main checkout against another worktree's tree has to work on trees from both sides of a path move. Why: F2. (This may be a note on new-rules-migrate-existing-work rather than a new lesson.)

Verdict: changes
