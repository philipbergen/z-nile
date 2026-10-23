# Review 001: R0043 (code mode)
Inputs: `impl-r43` at e109a46 (9e178c4 moves, 704e455 edits, e109a46 verification log), diffed against `origin/prep-z-nile-home` (b68a48e) after `git fetch origin`; c0114.md, R0043.md, both `check.sh` files, c0114's acceptance specs, design reviews and refutes 001-005; the architecture, testing, tracker and review skills; `./zn lessons --when build --full` and `--skill review --full`.

What I ran and checked:
- `z-nile/check.sh --full`: GATE PASSED, 1887 passed, 0 failed, 274 spec files, 74.7 s.
- `bash z-nile/.tracker/issues/c0114/check.sh`: 14/14. `bash z-nile/.tracker/rafts/R0043/check.sh`: 5/5.
- Sequestration: `git diff --find-renames=100% --name-status origin/prep-z-nile-home...HEAD` over the four item-root globs gives 108 `R100`, plus 2 `D` that are not item files: `tracker/templates/{issue,raft}/check.sh`, the templates moved to `z-nile/templates/` and edited (§10). No item `check.sh` or acceptance file changed.
- Overrides: the 56 `tests/acceptance` files the branch changes are exactly the 56 named in c0114's Regression guard, none missing and none extra. The 8 `tests/tooling` and 6 `tests/lib` edits match the "Edited, not promoted" list.
- Outside the item roots the branch is the same as `proto-c0114`, except for the four prep lessons.
- No tooling item was captured into `tracker/` after the prep: origin/main has no item that HEAD lacks, so step 9 has nothing to move.
- Repository safety (item 8), line by line:
  - `z-nile/lib/fence.sh`: the hooks default and the new missing-hooks refusal. The jail waiver needs all three markers, `PICKMAN_TEST_FENCE` must be non-empty, and the `.cache/*` match is quoted.
  - `pickman_guarded` answers `guarded` or `unguarded`. It returns 1 when the repository can't be read, so the publisher treats that as guarded.
  - `guarded()` in main.luau is wrapped in a pcall and publishes only on exit 0 with exactly `unguarded`.
  - `z-nile/lib/ac.sh` refuses before any check when `fence.sh` is missing. The `scripts/lib/ac.sh` forwarder exits 1 when its target is missing.
  - `tests/lib/fence.luau` sources the new path with `. … &&`.
  - The git hooks and `.repo.sh` moved as `R100` with path-only comment edits.
  - `repo-fence.spec`: its new `ALLOWED` entries are each for one file and one fixture call, it fails when the engine is present but won't load, and its root list falls back only when there is no engine.
  - `cachepaths`: the waiver line is listed as a read.
  - `stop.sh`: the root filter is anchored (`index($0, r) == 1`), and a bad registry leaves documents gated, never ungated.
  - `tests/lib/engine.luau`: `empty`'s callers all pass fixture dirs under `.cache`, and `copy` only reads from the checkout.
  - c0114's `check.sh` adds only reads (`./zn audit`, `git diff --quiet`).
  
  I found no fail-open path and no route to the real repository.
- Publisher: `counterOf` and the migration (`buildRead` serves the old counters as `z-nile/next`, so the go-up check compares against them; the tombstone is appended after `allowed`; `tracker/next` is refused from builds). Pre-c0114 engines' `refuseStale` returns early once origin has no `tracker/compaction.txt`. `paths.rewrite` checks segment boundaries and same-root. `new raft`'s one-project check runs online and offline.

### F1 [medium] classified.spec's live-check case carries a fixed floor (`expected >= 10`): once promoted, it turns main's gate red when fewer than 10 unfinished items have checks
Where: `z-nile/.tracker/issues/c0114/acceptance/classified.spec.luau`, "every unfinished item's check.sh still lists its checks through the forwarders" (`t.expect(expected >= 10).toBe(true)`). `./zn done` promotes it to `tests/acceptance/c0114/`.
Evidence: today 20 unfinished items have a `check "` line. Once R0043 is done (c0114 and R0043 move to `done/`), 18 are left. R0034 (f0065, R0034), R0035 (f0100-f0104, R0035) and R0041 (c0106, R0041) together hold 9 of them. When those three rafts finish, and fewer than one new prepared item with checks has arrived meanwhile, the count is 9 and the case fails. It fails in the full gate of whichever raft's `done` takes the count below 10 (that raft's own items have just left the count), and on main after it. The likely victim is a feature raft (R0035), which may not override a tooling chore's promoted spec (the override rule needs a chore). The floor exists to keep the case from passing vacuously (testing/no-vacuous-pass), which matters for c0114's own run. As a permanent regression spec it couples every future gate to how many preps happen to be in flight. It also means every gate runs the top level of every in-flight prep's `check.sh` (`members` calls and the like) in the real checkout. That is jailed on macOS, unjailed on Linux (a "check.sh files' own commands" exposure that grows with each new prep).
Critique: the spec is sequestered, so the author can't fix it here. The fix the author will be tempted to make is to lower the number (or edit it out in the forwarder-removal raft). Any fixed number has the same defect.
Consequences: a floor computed from the tree (for example, "at least one, and every one counted listed") leaves the case vacuous when nothing qualifies. A floor that holds only while c0114 itself is unfinished moves the check to where it matters. Either way it is an edit to a sequestered spec, which needs the user.
Recommendation: escalate to the user (execute-raft stop conditions). The options:
- (a) Approve a one-line change to the sequestered spec before `done`. Keep `expected >= 10` only while `c0114` is not in `done/` (its own run), and afterwards require only `listed == expected` plus the list-mode proof. Cost: one sequestered edit, recorded as a scope decision.
- (b) Keep the spec as written and capture a chore now (`--project z-nile`) that overrides the floor before the count can drop below 10. The rafts that would lower it get that chore as a dependency. Cost: an ordering rule across R0034, R0035 and R0041.
- (c) Accept the trap, knowing which raft's `done` will hit it.

Whichever is chosen, add a case that seeds a tree with fewer than 10 live items and shows the result the user picked.
Lesson: testing/no-vacuous-pass (the guard against a vacuous pass became a fixed threshold that a shrinking backlog trips)

### F2 [low] The testing skill still describes the pre-c0114 scope of the stop hook, the `.cache` writer list and the repo-fence scan
Where: `.claude/skills/testing/SKILL.md`: line 171 ("On stop: `z-nile/check.sh --affected` runs if `src/` or `tests/` changed"), line 141 ("every line in `scripts/` that names a `.cache` path … The list covers `scripts/` only"), and line 157 ("It scans what runs as a check (`tests/`, `scripts/` and every `check.sh` …)").
Evidence: `scripts/hooks/stop.sh` calls `scripts/check.sh --affected` (the path both sides of the move have, §8), and it gates `z-nile/` too. `cachepaths.ROOTS = { "scripts", "z-nile" }`. `repo-fence.spec` scans `zn` and `z-nile/` and every registry root's `check.sh`. Line 171 names a command the hook doesn't run. Lines 141 and 157 understate what the guards cover, and the review skill sends reviewers to exactly these lines for item 8.
Critique: the §10 rewrite renamed the paths mechanically but kept the old scope. docs.spec only checks for old paths, so it doesn't notice.
Consequences: none. These are unsequestered skill text.
Recommendation: line 171: "On stop: `scripts/check.sh --affected` (the forwarder; the removal raft switches it) runs if `src/`, `tests/` or `z-nile/` changed outside every project root." Lines 141 and 157: name `scripts/` and `z-nile/` (and `zn` for the scan), every root's `.tracker/` documents aside.

### F3 [low] The `scripts/lib/ac.sh` forwarder lost its executable bit, against §3; stale old-path comments remain in tests
Where: `scripts/lib/ac.sh` (100755 on the base, 100644 now). Stale comments: `tests/run.luau:39,80` ("`tracker.sh board`"), `tests/tooling/worktree-fetch.spec.luau:18` and promoted specs c0005, c0044, c0045, c0046 ("scripts/lib/fence.sh"), c0043/format ("scripts/tracker/main.luau"), c0049/par-stages (comment and spec title "scripts/lib/par.sh").
Evidence: §3: "Each is one command and keeps its old path's mode". `git ls-files -s scripts/lib/ac.sh` gives 100644. It is only ever sourced, so nothing breaks today.
Critique: an undocumented deviation, and the comments point readers at files that are now forwarders or gone (`scripts/lib/fence.sh`, `par.sh` and `scripts/tracker/main.luau` no longer exist).
Consequences: editing the promoted specs' comments would add files beyond the 56 named overrides, so leave those to the forwarder-removal raft.
Recommendation: restore mode 100755 on `scripts/lib/ac.sh` (or record the deviation in the issue's Addressed during execution). Fix the unsequestered, unpromoted comments (`tests/run.luau`, `tests/tooling/worktree-fetch.spec.luau`). Add the promoted ones to the removal raft's obligations in §3.

## Judged criteria (code mode only)
- JC1: pass. The PR description lists the one `c0114: move` commit, 9e178c4. `git show -M --find-renames=100% --name-status 9e178c4` shows 703 lines, every one `R100`, and `tracker/next` is not among them. The other commits move nothing: 704e455 has 33 `A` (forwarders, shims, `zn`, `projects.toml`, `roots.luau`, `.gitkeep`s, `tests/lib/engine.luau`) and 141 `M`, with no `D` and no `R`, so no file changes place. e109a46 is one `M` (c0114.md's log). No tooling item was captured during execution, so no step-9 move commit was needed.

Candidate lesson (for the lead): testing: a promoted regression spec never asserts a fixed count of live tracker items, because the backlog shrinks and grows independently of the code (R0043 review 001 F1); check: "Does any promoted case's threshold depend on how many items happen to be unfinished, prepared or in flight?"

Verdict: changes
