# Review 005: R0030 (design mode)
Inputs: worktree `prep-suite-split` at d84066a (`R0030.md`, its `check.sh`; c0083's document, `check.sh`, `acceptance/suites.spec.luau`, `experiments/`); design-review-001…004 and design-refute-001…004; the review, testing, tracker, ticket-prep and architecture skills; `tracker/architecture.md`, `tracker/game-design.md`. In the worktree, `scripts/tracker.sh check c0083` fails 0/9 for the right reasons: AC1–AC6 on the missing `@scripts/lib/suites`, and AC7–AC9 on the skills, greps and RC0 lines that execution has not edited yet. I spot-ran the prototype in a private `--no-hardlinks` copy (origin remote removed, `origin/main` set to c304408, non-fixture identity): `bash tracker/issues/c0083/check.sh` passes 9/9. No tripwire fired. The worktree is unchanged apart from this file.

Dropped from review-004: F1, F2 (both fixes hold for what they claim: a raft-shaped change selects 74, and `real-tree` no longer depends on its title. F1 below is a new hole in the `TRACKER_TREE_READERS` mechanism that F2's fix introduced.)

### F1 [high] `TRACKER_TREE_READERS` leaves out specs that read the real tracker tree, and AC2 forbids adding them
Where: c0083 Design, `textAffected` → "Tracker item folders" and "`TRACKER_TREE_READERS`" ("Today these are `tests/acceptance/c0082/real-tree.spec.luau` … and `tests/tooling/repo-fence.spec.luau`"); `suites.spec.luau` case "a tracker item's own files select only the specs that name them, plus the tree readers", lines 266–290 (two readers hard-coded, then "nothing else"); AC2; the testing skill's Suites paragraph ("a new spec of that kind joins that list")
Evidence: the design defines a tree reader as a spec "that read[s] the real tracker tree through a library or a walk, without naming the item's path". Four more promoted specs fit that definition on this tree. Each was selected for any item path under the old plain rule, through a token above the item folder. None of them is selected now:
- `tests/acceptance/c0034/locator.spec.luau` walks `{root}/tracker/{issues/active,issues/done,rafts/active,rafts/done}` in the real repo (`root` is `git rev-parse --show-toplevel`). It checks that no live `check.sh` uses the `"$A/.."` locator, and it runs every done item's `check.sh` in `AC_LIST` mode. That is the guard for `done`'s moved and rewritten `check.sh` files, the tree that `done`'s gate is there to check.
- `tests/acceptance/c0044/guard.spec.luau` walks `specs("tracker", …)`. Its header says it exists because "a prepped raft's acceptance spec that spells the old name literally breaks".
- `tests/acceptance/c0063/narrowed.spec.luau` and `tests/acceptance/c0103/narrowed.spec.luau` read `"tracker/issues/done/" .. renamed.id(…) .. "/check.sh"`. Their only path tokens are `tracker/issues/done` and `check.sh`.

On the prototype copy:
- I appended `# A="$A/.."` to `tracker/issues/done/c0008/check.sh` and added `tracker/issues/c0099/acceptance/x.spec.luau`, which names `tracker/issues/c0099/c0099-legacy-name.md`. `lune run scripts/affected --` on those two paths prints only `real-tree` and `repo-fence`. Running c0034 and c0044 directly fails both: "no live check.sh or the template uses the locator…" and "no spec under tests/ or tracker/ names a <ID>-<slug>.md document". So RC0, `done`'s gate on the moved tree, the Stop hook and `land` all pass this change.
- `--deps tracker/issues/done/f0031/check.sh` (the file c0063 reads) prints only the two listed readers.
- I added c0034 and c0044 to `TRACKER_TREE_READERS`, which is what the design's own definition requires. AC2 then fails at `suites.spec:289` with `expected "tests/acceptance/c0034/locator.spec.luau: true", got "… false"`. The sequestered case allows nothing beyond the Game init's selection plus its two hard-coded readers.
- The four missing specs cost about 8.5 s together (c0034 8.1 s, the others ≤ 0.1 s), against the 58 s that the item-folder rule saves.
Critique: three things go wrong here.
- **Wrong result.** The selector's result contradicts its own rule. It drops the guards on `done`'s moved `check.sh` files and on prepped acceptance specs. Until now, RC0's `--full` ran those guards on every raft.
- **Executability.** An executor who notices the gap can't fix it. Completing the list turns AC2 red, and AC2 is sequestered, so the only way forward is escalation.
- **Maintainability.** After promotion, every spec that "joins that list" (the testing skill's instruction) turns `tests/acceptance/c0083/suites.spec.luau` red and needs an Override.

The author will be tempted to add c0034 and c0044 to both lists. That repeats the mechanism's defect: a hand-kept list whose completeness nothing checks. Review-003 F1, review-004 F1 and F2, and this finding are four holes in text selection in a row.

The backstop is weaker than the Risks section assumes. CI's `--full` catches this on a PR, but a fix to a moved `check.sh` touches a sequestered file, which the Merging paragraph makes `BLOCKED:`. A direct push (`land`, `new raft`) is never seen by CI (`check.yml` ignores `tracker/**` on push), so the first person to see it is the next unrelated PR, as red on `origin/main`.
Consequences:
- The list has to be complete today, and it has to stay complete without depending on reviewers.
- The spec can't hard-code its contents. It has to check that the list matches what the tree reads.
- A scan that finds real-tree readers is heuristic. Fixture specs also write `` `{wt}/tracker/…` ``, so the scan needs a precise trigger: a `readDir`, `isDir`, `readFile` or walk whose argument starts with a bare `"tracker` literal or with the toplevel root, not a fixture variable.
- The alternative, keeping `check.sh` and `acceptance/**` on the plain rule, brings back the 60-spec noise on `done`'s move, which refute-004 measured and rejected. The list approach is the cheaper one, but only if it is complete.
Recommendation:
- **Complete the list in prep.** Put `tests/acceptance/c0034/locator.spec.luau`, `tests/acceptance/c0044/guard.spec.luau`, `tests/acceptance/c0063/narrowed.spec.luau` and `tests/acceptance/c0103/narrowed.spec.luau` alongside the two current readers. Re-audit with a recorded, reproducible grep (an E8 in Unknowns). For example: every spec with an `fs.readDir`, `fs.readFile`, `fs.isDir` or walk call whose argument is a relative `tracker` path or `{root}/tracker` with `root` from `rev-parse --show-toplevel`. List what it found and why each hit is in or out.
- **Export the list** (`suites.TRACKER_TREE_READERS`). In the item-folder case, derive the "nothing else" allowance from the exported list instead of the two literals. Keep explicit `exists` and membership asserts for the six audited specs, so dropping one still fails. Adding a seventh spec then needs no Override.
- **Add a completeness case** that runs the E8 scan over `tests/` and fails when a spec it finds is not on the list. That case makes "a new spec of that kind joins the list" enforceable. Because it scans every spec, any spec change selects it.
- **Add mutants and fix the documents.** Add Rules rows with the mutants "c0034 not a tree reader" and "a scanned real-tree reader missing from the list", both killed on the prototype. Update the Design's "Today these are" sentence, the Scalability raft-shaped count (74 becomes 78), and E2's item rows.

Verdict: changes
