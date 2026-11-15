# Review 012: c0263 (design mode)
Inputs: prep `prep-ticket-provenance` at f99df9bb (`c0263.md`, `check.sh`, `acceptance/{provenance,publish,record,remap,remap-shapes}.spec.luau`, `experiments/{proto.patch,mutants.py,folder-move.sh}`, `harvest.md`, `design-review-008..011.md` with `design-refute-008..011.md`); origin/main bc8c24b9. Prototype `proto-c0263-raft` at e2de5e0c: `git diff 0ea4a484 e2de5e0c -- z-nile/engine z-nile/README.md z-nile/skills` is byte for byte `experiments/proto.patch` (`cmp`), and its five spec copies equal the sequestered ones. `experiments/split/` was not reviewed (sibling hand-off). Reviews 003 to 007 were read as history only.
Dropped from review-011: none. Every finding was answered, and I checked each answer (Notes). F1's guard and F4's refusal are new mechanisms, and each has a hole (F4 and F1 here).
Capture: `./zn capture c0263` prints `(no capture commit: first add)`, so it is not a confirmed capture. Judged from history: the Problem is unchanged apart from its dated decision lines; the split's `Scope decision (user, 2026-11-08)` covers what moved to c0280 to c0284. No scope finding.
Runs, all through `./zn run --time`, in a scratch clone of e2de5e0c under the session scratchpad (its `origin` a throwaway bare copy; never the real repository):
- (a) `probe012.spec`, run 1 (P1, P6), and run 2 (P2 to P5, each on a fresh worktree so that no case's commits leak into another's merge base): `./zn sync` driven through the shapes below.
- (b) `probe012c.spec`: plain `git merge` inside a stopped rebase (P6) and a stopped cherry-pick (P7), i.e. what `mergeRef` does without its guard.
- (c) Plain git and reads: the publish rate of origin/main; `grep` of the five specs and of the promoted specs; a script that compares `mutants.py` with the Rules table.

### F1 [high] The way through a stopped sync fails whenever origin/main moves first, which here is about once a minute. The refusal's own advice (`git merge --continue`) cannot work, and the message says "merge aborted" when nothing was aborted
Where:
- Behaviour 5, *Refuse first*: "A merge of this very `ref` already in progress … is finished". Behaviour 5, "When a sync stops": `git merge origin/main`, resolve, `git add`, "run `./zn sync` again, which finishes that merge".
- AC6: "a hand merge of `origin/main` with only records left is finished".
- zz-rules, Provenance (the same hand path).
- Prototype `mergeRef` (main.luau:452-457) finishes only when MERGE_HEAD equals `rev-parse <ref>`, and `cmd.sync` fetches before it calls `mergeRef`. `mergeOrigin`'s message (main.luau:561).
- The round-4 lesson note in zz-arch/guard-no-is-explicit: "finish only a merge of the very ref it was asked for".

Evidence:
- Run (a) P1. A record conflict was left by a hand `git merge --no-commit origin/main`. Then another terminal published one unrelated file, and then came `./zn sync`:
  - `P1 sync ok false | MERGE_HEAD present | unmerged: true`.
  - The output was: `merging origin/main failed (merge aborted; anything this command published is already on origin/main): a merge of another branch is in progress: finish it (git merge --continue) or abort it (git merge --abort), then run this again // merge by hand: git merge origin/main, resolve every conflict except provenance.md …`.
  - Following that advice: `git merge --continue` gave `error: Committing is not possible because you have unmerged files … U pickman/.tracker/issues/c0061/provenance.md`.
- Publish rate: `git log origin/main --first-parent --since="2026-11-07 00:00" --format=%ct` gives 290 gaps, with a median of 53 s and a 25th percentile of 13 s (mostly `tracker: spend …`). So a hand resolution that takes longer than about a minute nearly always meets a newer origin/main when sync fetches.
- Every command that merges after it publishes (`record`, `spend`, `status`, …) moves origin/main itself before `mergeRef` runs. So during a hand merge it always refuses.
- record.spec (viii) passes only because nothing publishes between its hand merge and its sync.

Critique:
- The documented way through, for every sync that stops on another file, fails in this repository's normal operation, and AC6's clause is unmet for a real input.
- The user is then left with three bad options:
  - abort, losing the resolutions, and race again;
  - unite the records by hand, which is the work the design removes;
  - follow the message: `git merge --continue` fails, and the obvious next step, `git add provenance.md`, commits conflict markers.
- Review 011 F4 proposed equality as a feature ("a stale hand merge still refuses"). But an older origin/main is not another branch: finishing it and then merging the new tip gives the same result as merging the new tip.

Consequences of the obvious fix ("accept MERGE_HEAD when it is an ancestor of `ref`"):
- The engine then commits the user's hand merge and must still bring in the newer tip: a second, ordinary merge. When that second merge stops, only it is aborted, and the finished hand merge stays committed. The message must say so.
- A hand merge of a branch that main already contains is finished too. That is harmless, because its commits are in origin/main, but state it.
- The texts must tell apart a refusal (nothing aborted), an abort, and a stop left in progress.

Recommendation:
- In `mergeRef`, finish a merge in progress when `git merge-base --is-ancestor MERGE_HEAD <ref>` holds, settled against MERGE_HEAD as now. Then merge `ref` by the ordinary path. Refuse any other MERGE_HEAD.
- `mergeRef` returns whether it aborted. `mergeOrigin` and `land` print "merge aborted" only then.
- The hand-merge trailer is printed only for a conflict in another file. The refusals, the compaction stop and the id-change stop give only their own way through. A refusal never advises `git merge --continue` while paths are unmerged.
- Behaviour 5, AC6, zz-rules and the lesson note say "a merge of `origin/main`, or of an older commit of it".
- record.spec gets case (ix), P1's shape: the sync exits 0, the record reads Base, Main, Ours, MERGE_HEAD is gone, and the file main published last is in the tree. (vii) stays a refusal.
- A Rules row with the mutant "resumed only when MERGE_HEAD equals ref", which fails (ix).

Lesson: z-design/design-the-execution-window (main writes during the window the hand path needs); z-design/instructions-runnable-where-they-run (the refusal's advice can't be followed).

### F2 [high] `./zn sync` silently discards an uncommitted change to a record the branch changed. `mergeRef` rewrites every record it settles on disk, including the ones git's merge never touched
Where:
- Behaviour 5, *Write*: "a record goes beside the item's one document in the merged tree".
- Prototype `mergeRef`: `fs.writeFile(dest, plan.text)` and `git add` for every `write` plan (main.luau:525), and `git rm -f` of the id's other paths (main.luau:531).
- `cmd.sync` does not require a clean tree, and neither do the publishing commands that merge afterwards.

Evidence: run (a) P5.
- A fresh branch commits c0062's record (`Committed`), then appends a row that is not committed (`Uncommitted`). Main publishes an unrelated file.
- `./zn sync` gives `P5 sync ok true | HEAD subject Merge remote-tracking branch 'origin/main' into raft-p5`, then `P5 status after sync:` (empty), then `P5 record after sync: … human:Committed …`: the uncommitted row is gone, with nothing printed.
- The same shape with plain `git merge --no-edit origin/main` (the merge `sync` made before this layer) gives `P5 plain git merge ok true | record: … human:Committed … human:Uncommitted …`.
- Why: settling sees "ours changed it, theirs did not", and writes ours' committed text over the working file. Git's merge leaves an untouched dirty path alone, and refuses a merge that must touch one.

Critique: a merge must never lose work the user has not committed. Git guarantees that, and the engine's extra writes break it. The trigger is uncommon: rows are normally written by commands that commit them. But the loss is silent, exit 0 and a clean status. zz-execute runs `./zn sync` at Phase 0 and Phase 5, and agents publish (`spend`, `status`) mid-work, which merges afterwards.

Consequences:
- Skipping the write when the text is unchanged covers P5.
- A write that must change a dirty path git did not touch (git paired theirs' change elsewhere) has to stop.
- Unmerged paths must be excluded from the dirty test, because their worktree holds git's conflict text.
- In the resumed path, the index holds the user's resolutions, so the test there is the worktree against the index.
- remap is unaffected: it refuses a dirty tree.

Recommendation:
- Write a record only when the settled text differs from the merged index's entry at that path (`git rev-parse :<path>` against `git hash-object`).
- Before writing or `git rm -f` of a path that is not unmerged, stop (and abort a merge we started) when the worktree differs from the index there (`git diff --quiet -- <path>`). The message names the path: commit or stash it.
- Writing each record into the index first (`hash-object -w`, `update-index --cacheinfo`) and then `checkout-index -f` also closes the window where an error between `fs.writeFile` and `git add` leaves an untracked file behind that `git merge --abort` does not remove.
- record.spec gets case (x), P5's shape: the sync exits 0, the worktree still holds the uncommitted row, `git status` shows the record modified, and HEAD's record is the committed text.
- A Rules row with the mutant "merge: writes every settled record", which fails (x).

### F3 [medium] A raft that `recombine` retires: the sync stops, saying an id changed, where plain git merges it cleanly with the row in the retired folder
Where:
- Behaviour 5, *Collect the ids*: "A retired raft's record is not an item record in that layout, so a conflict there stops the merge".
- `recordIdOf` via `publish.itemPath`, which rejects `rafts/retired/<R-id>/`. Audit's `STATES` includes `retired/`.
- `cmd.recombine` moves a retired raft's folder to `<root>/rafts/retired/` on its branch (main.luau:2260-2297).

Evidence: run (a) P2.
- R0161 (a backlog raft) has a record on main. Our branch moves `rafts/R0161` to `rafts/retired/R0161`, which is what `recombine` does. Main then publishes a row into `rafts/R0161/provenance.md`.
- `./zn sync` gives `P2 sync ok false | HEAD moved false`, with the reason `R0161: one side changed the record and the other has none under this id (an id changed: after a compaction run ./zn remap, after a renumber merge by hand) // Automatic merge went well; stopped before committing as requested`.
- Plain `git merge` on the same tree gives `ok true | live folder left false`, and `retired/R0161/provenance.md` holds `Base, Main`.
- Git reports no conflict here, so the design's sentence is not what happens. Settling finds no record for R0161 on our side (the retired path is not a record), so it reads our move as a deletion.

Critique:
- A raft's record exists so that whole-raft events (c0250's block, a rank) have a home.
- A rafting PR that retires a backlog raft is open while those rows are published. Its sync then stops with a wrong reason, and the reason points at remap or a renumber, neither of which applies.

Consequences:
- The read side must treat `retired/` as a raft's place:
  - the record layout used by the merge (and audit, which already scans it);
  - the document search in `planRecords`.
- The write side must not: `publish.allowed` keeps refusing `retired/`, so `./zn record` never publishes into a retired raft. A flag or a second predicate is needed, not a wider `itemPath`.
- Issues in `retired/` stay an audit error.

Recommendation:
- One read-side predicate for "an item's record" that accepts `rafts/retired/<R-id>/provenance.md`, used by the merge, remap's settling and audit.
- `planRecords` finds a raft's document in `retired/` too.
- Rewrite the Behaviour 5 sentence.
- record.spec gets P2's shape: the sync merges, the row is in `retired/R…/provenance.md`, and there is no live folder.
- A mutant "merge: ignores retired records".

Lesson: zz-test/seed-every-enumerated-case (the merge walks `""`, `active/` and `done/`, while the states are four).

### F4 [medium] The compaction guard fires only when both sides changed records. When only the side numbering items the old way changed one, the row lands beside another item: exit 0, audit clean
Where:
- Behaviour 5, *Stop across a compaction*: "With records changed on one side only, every record is that side's, which is git's result, and the merge goes on."
- `provenance.compactionProblem` (provenance.luau:349).
- provenance.spec:356 pins `compactionProblem(nil, "c0042 c0041\n", true, false) == nil`.
- The round-4 note in zz-rules/item-history-spans-moves-and-compaction.

Evidence: run (a). Items c00x1, c00x2 and c00x3 carry `identity: Alpha`, `Beta` and `Gamma` in a line with no id token.
- **P3.** A stale branch adds Beta's first record at c0072. Main compacts: c0071 goes, Beta becomes c0071 and Gamma becomes c0072. Main changes no record.
  - The sync gives `P3 sync ok true | status clean true`.
  - Then `P3 c0071 identity Beta | record (none)` and `P3 c0072 identity Gamma | record … human:ForBeta …`, and `P3 audit ok true`.
  - Git's own `merge-tree HEAD^1 HEAD^2` puts the file at `c0072/provenance.md` too.
- **P4.** The mirror case: the compaction's own branch, with no record of its own changed, while main publishes Beta's row at the old c0082. The sync gives `P4 sync ok true`, then `P4 c0082 identity Gamma | record … human:MainForBeta …`.
- Run 1 showed the limit. The changed flags are global, so once any record changed on both sides since the base the guard stops. The hole is open only while the side that did not compact is the only one with record changes. That covers the window before records are common, the compaction's own branch while main changed none, and a young branch.

Critique:
- The text the record carries is "that side's", but the merged tree numbers items the other side's way. "Which is git's result" is true, and git's result is wrong.
- For c0283 this would be an `approved` row on a ticket nobody approved.
- I rate it medium rather than high for three reasons: it is no worse than git; it is narrow; and the existing rule ("a branch that changed tracker/ runs ./zn remap", `refuseStale`) covers it in principle, though `sync` does not enforce it.

Consequences: the question is which side compacted.
- Records changed by the side that compacted are already in the merged numbering, so they are safe.
- Records changed by the other side are not.
- If both sides compacted, the merge is never safe when any record changed.
- (vi) still merges, because our side neither compacted nor changed a record.
- An alternative is to enforce `refuseStale`'s rule in `mergeRef` (maps differ and our side changed anything under the roots). It is coarser, it covers every file and not only records, and it may override c0081 specs: weigh it if you want the general fix.

Recommendation:
- `compactionProblem(baseMap, oursMap, theirsMap, oursChanged, theirsChanged)` stops in two cases:
  - when one side's map differs from the base's and the other side changed a record;
  - when both differ from the base's and any record changed.
- Change provenance.spec:356 and add the pure cases for both directions.
- record.spec gets P3's and P4's shapes: each stops, naming `./zn remap` (P4: compact again).
- A mutant "guard ignores a one-sided change", which fails P3.
- Rewrite the Behaviour 5 sentence, zz-rules and the lesson note.

Lesson: zz-rules/item-history-spans-moves-and-compaction ("never infer identity across an id change").

### F5 [medium] The refusal of a rebase, cherry-pick or revert in progress has no case. Without it, a sync inside a stopped rebase puts a merge of origin/main into the user's rebased history
Where:
- Behaviour 5, *Refuse first*; AC6 ("a merge or other git operation of another kind already in progress is refused and never aborted").
- `mergeRef` main.luau:459-462.
- The Rules row "a merge or other git operation in progress is not ours", whose mutants cover only MERGE_HEAD.

Evidence:
- `grep -n "rebase\|cherry\|CHERRY\|REVERT\|bisect" acceptance/*.luau experiments/mutants.py` prints nothing. No case creates those states, so a mutant that deletes the three checks passes all five specs.
- Run (a) P6: the prototype refuses a rebase stopped at `edit` (`a cherry-pick, a revert or a rebase is in progress`, HEAD unmoved), so the guard works.
- Run (b) P6, the same with plain `git merge --no-commit origin/main` (the unguarded body): `plain merge ok true | MERGE_HEAD true`, then `commit ok true | rebase still in progress true`, then `rebase --continue ok true | branch log: p6 two / Merge remote-tracking branch 'origin/main' into HEAD / p6 one`.
- Run (b) P7: git itself refuses to merge during a cherry-pick (`fatal: You have not concluded your cherry-pick (CHERRY_PICK_HEAD exists)`). So the rebase check is the part that matters.

Critique: a guard whose wrong implementation passes check.sh. Its failure is recoverable (`git rebase --abort`), hence medium.
Consequences: none beyond the case.
Recommendation:
- A record.spec case: a rebase stopped at `edit` (`-c sequence.editor="sed -i.bak -e 1s/^pick/edit/" rebase -i`). The sync refuses, HEAD is unmoved, and `rebase-merge` is still there.
- A Rules row with the mutant "merge: ignores a rebase in progress".

Lesson: zz-test/guard-needs-its-own-case.

### F6 [low] Texts that disagree with the prototype and with each other
- **A one-sided edit of an old row.** Several texts say it stops the merge:
  - AC6 ("a side that edited, removed or reordered an old row … stop the merge");
  - zz-rules ("It stops … for … a side that edited, removed or reordered an old row");
  - the Limit ("a sync after one stops at … a changed old row").

  But `settle` takes a one-sided change after parsing only (provenance.luau:321). That is right: a `renumber` rewrites ids in old rows of records main never touched. Say "when both sides changed the record" in all three.
- **The README.** Behaviour 7 and AC7 say the README names `--actor`/`ZN_ACTOR`, the session variables and the union through `./zn sync`. The prototype's README line (z-nile/README.md:117) names none of them, and the docs case checks only `provenance`. Either the README line names them, or AC7 and Behaviour 7 say the README points to zz-rules, Provenance (it does). The needle follows.
- **remap's stop.** The text says to unite the records by hand, and that is the only way after a remap: its merge base is pre-compaction, so `./zn sync` would stop on the compaction guard, and `remap` refuses a second run. zz-rules' general "run `./zn sync` again: it finishes that merge" should exclude it.

Lesson: z-design/restated-rules-move-together.

### F7 [low] Assertions that cannot fail, and a compaction that every later case inherits
- **(vi)** (record.spec:842) asserts "every record is main's" with `rec("c0043", "Shared")`. Main's renumbered c0044 record is byte for byte the base's c0043 record, so a merge that kept ours (or the base's) passes as well. (vi) still pins "merges", but its content assertion doesn't. Give c0044 a row of its own and expect it at c0043.
- **Two vacuous expects:** `guarded`'s `t.expect(id ~= "").toBe(true)` (record.spec:683) and remap-shapes' `t.expect(trOk(a, { "audit" }) ~= nil).toBe(true)` (remap-shapes.spec:167). The latter is pinned only by `trOk` raising. Drop them, or assert something.
- **The map left on main.** (v) and (vi) push a compaction map to main for every case after them. A later case whose worktree changes a record before it syncs would stop on the compaction guard instead of testing its own shape. Today every such case either syncs first or changes no record. Say so in a comment, or seed the map before setup.

Lesson: zz-test/no-vacuous-pass.

### F8 [low] remap settles in the real index (read, not run)
Where: `settleRemapRecords`: `git read-tree <merge-tree's tree>` … `git reset --quiet HEAD` (main.luau:3314-3336).
Evidence: between those two calls the real index holds the merged tree under a HEAD that lacks it. A kill of the process there (Ctrl-C, a `./zn run` limit) leaves `git status` showing the merge staged and its reverse unstaged. Review 011 F2 recommended a temporary index (`GIT_INDEX_FILE`), which has no such window.
Recommendation: build the tree with `GIT_INDEX_FILE=<mktemp>` (the same five commands), and remove the file afterwards. No case is needed.

Notes (not findings):
- **Round-4 answers checked.**
  - F1: the guard exists, with (v), (vi) and the pure cases. F4 here is its hole.
  - F2: one routine (`planRecords`) serves `mergeRef` and remap, and remap-shapes A, C and D run.
  - F3: remap-shapes D.
  - F4: (vii), (viii) and the never-aborted case. F1 here is its hole.
  - F5: one predicate, `recordIdOf` via `publish.itemPath`. F3 here is its missing state.
  - F6: the raft record case.
  - F7: `settle` and `compactionProblem` are in Interfaces; both-deleted is `remove`; the ids are taken in discovery order.
  - F8: the rows are counted.
  - F9: step 1 says `--3way`, and the Edge cases say "Limit".
- **Counts and size.** 7, 3, 29, 8 and 5 cases match the files. All 75 mutant names in `mutants.py` appear in the Rules table (a script compared the lists: 0 missing). The patch adds 823 lines and removes 23, and `size: 850` fits.
- **Merge edges that hold** (read, or run where marked):
  - criss-cross merges: one base, then the multiset union or a stop when a side does not extend it;
  - deleted on both sides: `remove`;
  - an empty or whitespace-only record: `parse` refuses it;
  - a mode change: the texts compare equal, so it is kept;
  - a symlink: its text fails `parse` when it changed;
  - an item moved on one side and its document edited on the other: git follows the move, and the record goes beside the merged document;
  - MERGE_HEAD with a clean index: finished when it equals `ref`;
  - a stash: no state; a conflicted `stash pop` leaves unmerged files and no MERGE_HEAD, and git then refuses to merge;
  - a cherry-pick in progress: git refuses (run, P7);
  - `git rm -f` of a modified path: git's own merge refuses first when it must touch that path;
  - remap on a dirty tree: `refuseDirty`, and remap commits with `add -A` before `read-tree`;
  - bisect: not in the list (a detached HEAD), with the same exposure as the old code.
- **`git commit --no-edit` and hooks.** The real repository's `.git/hooks` holds only samples, and `core.hooksPath` is unset.
- **Overrides "none": still plausible.**
  - No promoted fixture holds a record.
  - `git grep -nF -e "resolve it with" -e "published, but merging" -e "merge aborted" -e "git merge origin/main and retry" -- z-nile/tests pickman/tests tests '*/tests/acceptance'` (excluding c0263) prints nothing, so no promoted needle names the texts the prototype changed.
  - The owed `z-nile/check.sh --affected` (Implementation step 1) stands. Every fix above adds cases and changes no promoted answer. F4's alternative (enforcing `refuseStale` in `mergeRef`) might change one.
- **Repository safety.**
  - The specs write only `.cache` fixtures and commit as `@example.invalid`.
  - `mutants.py` edits the detached copy `proto-c0263-mut` and restores it.
  - My probes ran in a scratchpad clone with a throwaway origin.
- **Lessons.** The round-4 commit added three notes, and each is a lesson another raft could fail. Two of them now restate the rules F1 and F4 find holes in ("finish only a merge of the very ref"; "stop when they differ and both sides changed records"). The lead should amend them with the fixes.

Candidate lessons (for the lead):
- **A helper that finishes a user's half-done git operation must survive the ref moving in between.** The check: if origin/main moves between the user's step and the helper's (here every 53 s at the median), does the documented path still work, and does the refusal's advice run? (F1)
- **A merge helper writes only what changed.** Rewriting a file git's merge left alone discards the user's uncommitted edits. The check: for each path the helper writes or removes, does it compare with the index, and refuse a path with uncommitted changes? (F2)
- **A guard on "both sides changed X" asks which side is in which numbering.** A one-sided change is safe only when the changing side is the one whose ids the result uses. (F4)

Verdict: changes
