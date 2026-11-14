# Review 011: c0263 (design mode)
Inputs: prep `prep-ticket-provenance` at 880c9656: `c0263.md`, `check.sh`, `acceptance/{provenance,publish,record,remap}.spec.luau`, `experiments/{proto.patch,mutants.py,folder-move.sh}`, `design-review-008..010.md` with `design-refute-008..010.md`, `harvest.md`. Prototype `proto-c0263-raft` at e4f0efec: `git diff 0ea4a484 e4f0efec -- z-nile/engine z-nile/README.md z-nile/skills` is byte-identical to `experiments/proto.patch`, and its four spec copies are byte-identical to the sequestered ones. origin/main ae926c87. Reviews 003 to 007 were read for history only.
Dropped from review-010: F1 (`git rm -f`; the UA, DU, UD and cross-item cases read the disk and `./zn find`), F3 (remap now unites; its mechanism is F2 here), F4 (the three stop cases and their mutants exist), F5 (both new needles have 0 hits on origin/main). F2's mechanism holds for `sync` within one id scheme; its premise fails across a compaction (F1 here). F6 is repeated in part in F9.
Capture: `./zn capture c0263` prints `(no capture commit: first add)`, so it is not a confirmed capture. Judged from history: the Problem is unchanged apart from its dated decision lines, and the split's `Scope decision (user, 2026-11-08)` stands. remap now takes the full-scope answer, so it needs no scope line.
Runs: every probe ran through `./zn run --time`, never in the real repository.
- (a) `mtpair.sh`, plain git in a scratch repository: the cross-item shape run through `git merge-tree --merge-base`, which is remap's merge.
- (b) `probe011.spec`, `probe011b.spec` and `probe011c.spec`, in a scratch clone of e4f0efec (under the session scratchpad, its `origin` a throwaway bare copy). They drive the prototype's `./zn sync` through these shapes:
  - P1: a compaction that reuses an id;
  - P2: a `provenance.md` in an id-named folder that is not the item's folder;
  - P3: an id renumbered downward;
  - P4: a hand merge in progress;
  - P5: a raft's record when `done` moves the raft.
- (c) Two mutants in the same clone, each restored afterwards:
  - "mergeRef ignores raft records", run with record.spec and P5;
  - "remap accepts a non-record conflict beside a record", run with remap.spec, `tooling/remap-once` and `probe011remap.spec`. That probe is remap.spec's fixture, plus main editing the document line the branch edited.
- (d) `r011union.luau` and `r011settle.luau`, which call the pure module directly.
- (e) The promoted `tooling/spend`, `c0116/compact-record`, `c0070/board-refresh`, `c0116/plan-cli` and `c0114/publish-roots` on e4f0efec: 32 passed, 0 failed.
- (f) `git apply --check` of `proto.patch` against origin/main, with and without `--3way`. These were plain git commands, run in a temporary detached worktree in the scratchpad that was removed and pruned afterwards.

### F1 [high] Across a compaction, an id names another item, and `mergeRef` settles the two as one. `./zn sync` exits 0 and leaves our row in the other item's record. The design says a compaction stops the sync
Where:
- Behaviour 5: "changed on one side and absent on the other (the id changed: a `renumber` or a compaction)", and "A compaction on main is the same stop, and `./zn remap` is the way through".
- Edge cases, last bullet.
- zz-rules Provenance: "An id changed on one side (a `renumber`, or a compaction: run `./zn remap`) stops the sync, naming the id".
- Prototype `mergeRef`: it never reads `z-nile/compaction.txt`.
- `cmd.sync`: it never calls `refuseStale`.
- `cmd.land`: it calls `refuseStale()` after `mergeRef(base)`, when the merged map already equals origin's.

Evidence: run (b) P1.
- The base holds c0030 (title Alpha) and c0031 (title Beta). Each has a record with the same single row, `| 2026-11-08 10:00 | ranked | human:Shared | rank=1 |`, and a header that names its own id.
- Ours appends `OursForAlpha` to c0030's record.
- Main does to these two items what `compact` does: `ids.plan` numbers items from 1, and `compact.apply` rewrites every id token in every `.md` under the roots, so the record headers are rewritten too. That makes c0030 → c0029 and c0031 → c0030.
- `./zn sync` prints `P1 sync ok=true`, then `synced to 83ebea5`. Afterwards:
  - c0029 (Alpha) holds only `Shared`;
  - c0030 (Beta) holds `Shared, OursForAlpha`;
  - `git status` is clean, and `audit: 0 errors`.

Why it happens:
- After the rewrite, Beta's record at c0030 is byte for byte Alpha's base record. `settle` reads that as "theirs unchanged", takes ours, and writes it beside c0030's document, which is now Beta's.
- When the record under the reused id merely starts with the base's rows, `union` accepts it, and the same thing happens with main's rows mixed in.

Why it is likely:
- c0282 writes one `rafted` row per ticket of a rafting PR, from one command: the same minute, actor and `raft=<R-id>`. It also writes one `delivered` row per ticket at the raft's `done`.
- The tickets of one raft get adjacent ids, and a compaction that closes a gap below them shifts each one onto its neighbour's old id.
- zz-execute Phase 0 step 1 says to run `./zn sync` first in a reused worktree.

Critique: this is the fourth round with a hole in the merge mechanism. Round 4 keys the merge on the item's id, so it relies on the id meaning the same item on both sides. A compaction reuses ids, which breaks that, and the lesson below says exactly this.
- The "absent on the other side" stop catches a renumber, because the new id is one neither side held. It does not catch a reuse.
- The tempting fix is to compare the headers. It fails, because `compact` rewrites the headers.

Consequences: the merge must first establish that both sides number items the same way, which means the same compaction map.
- **A compaction's own branch** (our side has the new map, and main has moved on) is the mirror case and must stop too. Its way through is to compact again on the current main.
- **Only one side changed records.** Then every record is settled to that side's version, which is git's result anyway, so the merge is correct.
  - That covers a branch that changed no record, and every promoted fixture, since none holds a record. So no promoted case changes.
- **After `./zn remap`** the maps agree. remap's own merge uses a base remapped to the same ids, so the id is the item there too (F2).

Recommendation:
- In `mergeRef`, after the `--no-commit` merge and before settling, read `ids.MAP_FILE` at HEAD and at MERGE_HEAD (absent counts as empty).
- When the two maps differ and both sides changed a record since the base, abort. The message names the ids and says: "the merge crosses a compaction: run `./zn remap` (on the compaction's own branch, compact again on the current main)".
- Put the decision in a pure function (in `provenance` or `ids`), so that a pure case pins it.
- Rewrite Behaviour 5, the Edge case and zz-rules to say: a compaction is refused before any record is settled; a renumber, to an id neither side holds, stops by the "absent on the other side" rule.

record.spec gets two cases:
- (v) P1's shape, a reused id whose record is byte-identical to the base: the sync stops with the tree as it was, and the message names `./zn remap`.
- (vi) The same compaction with no record changed on our side: the sync merges, and every record is main's.

Mutant: "merge: settles across a compaction" (the check removed), which fails (v).

Lesson: zz-rules/item-history-spans-moves-and-compaction ("never infer identity across an id change"; its c0120 note: "a check keyed by item id … refuses instead, naming the renumber (z-nile/compaction.txt)"; "seed a fixture with … a compaction with a reused number").

### F2 [high] remap still merges records the way round 3 retired: by path, only where git reports a conflict. `git merge-tree` pairs our row with another item's record and exits 0, and remap commits that. For remap, AC6 and check.sh's AC6 label are unmet, and remap.spec still passes
Where:
- Behaviour 5's remap sentence.
- AC6: "every merge … (`sync`, `fold`, `land`, and `remap`'s own) settles each record either side changed by its item id, on clean merges too … however git paired the files".
- check.sh's AC6 label: "… and remap's own) settle each changed record by its item id".
- zz-rules: "`remap` unites a record both sides appended the same way".
- Prototype `cmd.remap`: it calls `uniteRemapRecords` only when `not mt.ok`.

Evidence:
- **Run (a).** The base record of c0016 is `[Shared]`; ours appends `Ours`. Main appends M1 to M3 to c0016's record, creates c0017's record `[Shared]`, then moves c0016 to `a/`.
  - `git merge-tree --write-tree --merge-base=<base tree> ours main` gives `merge-tree exit 0`.
  - The merged tree's c0017 record holds `Shared, Ours`, and `a/c0016`'s holds `Shared, M1, M2, M3`.
  - A clean merge-tree never reaches `uniteRemapRecords`, so remap commits that tree.
- **The folder-move shapes.** UA, DU and UD give a conflicted path with one side's stage missing. `uniteRemapRecords` refuses those (`if not ours or not theirs then return nil`), so remap stops where `sync` unites.
- **A mutant survives.** Replacing `provenance.union(blob(1), ours, theirs)` with `provenance.union(nil, ours, theirs)` gives the same text on remap.spec's input (run (d): `remap.spec input, base vs nil equal: true`).
  - Without the base, an edited base row is kept beside the original instead of refused (run (d): the union holds `Base, Main, Eve, Ours`).
- **It works in the worktree.** `uniteRemapRecords` writes merge-tree's conflicted tree over the worktree with `read-tree --reset -u` (which overwrites untracked files in its way), then runs `reset --hard HEAD`.
  - In a sparse checkout, `git add` refuses a path outside the cone, and remap then reports a record conflict instead.

Critique: there are two merge mechanisms for one file, and remap's is the one round 3 retired for its holes. In remap the id does name the same item, since the base and the branch are remapped onto main's ids, so settling by id would be sound there. Only the mechanism is wrong. The tempting fix, also handling the file-location stages, repeats round 2's per-shape rule.

Consequences: one settling routine over three trees, used by `mergeRef` (with the real index) and by remap (with a temporary index):
- The ids come from `git diff --name-only --no-renames <baseTree> HEAD` and `<baseTree> origin/main` (diff takes trees), plus the conflicted record paths.
- Each id's record is found by `locate` over `ls-tree -r --name-only` of each of the three trees, and its document over the listing of merge-tree's tree.
- The writes go into a temporary index:
  - `GIT_INDEX_FILE=<tmp> git read-tree <tree>`;
  - `git hash-object -w --stdin` for the settled text;
  - `git update-index --cacheinfo 100644,<blob>,<path>` to write it, and `--force-remove` for stale paths;
  - `git write-tree`.
- Nothing touches the worktree before the merge commit.
- A stop keeps today's "remap committed, but merging origin/main conflicts" path, which `tooling/remap-once` pins.
- F1's guard isn't needed here: the map is applied to the base and to the branch.

Recommendation: adopt that routine, and change zz-rules' "the same way" and the AC6 label to whatever remap then does.

remap.spec gets these cases:
- (a) The cross-item shape: main readies the item and writes a near-identical record for another item, and merge-tree exits 0. The row stays with its own item, and the other item's record is exactly main's.
- (b) Main readies the item after the branch point, and both sides append: the record is united at the `active/` path.
- (c) Ours edits a base row: remap stops.

Rules rows for these mutants:
- "remap settles only conflicted paths", which fails (a);
- "remap drops the base stage", which fails (c).

Lesson: z-design/histories-checked-against-a-real-life, z-design/restated-rules-move-together.

### F3 [medium] remap's "any other conflict stops" has no case. A mutant that skips conflicted paths that are not records commits a document full of conflict markers, and remap.spec and remap-once both pass with it
Where:
- Behaviour 5 ("any other conflict stops it as before") and AC6 ("and any other conflict, stop the merge").
- `uniteRemapRecords`, its first loop.
- The Rules table: no row has it.

Evidence: run (c). The mutant is `if not sha or not path then return nil end; if not string.match(path, "/provenance%.md$") then continue end`.
- With it, remap.spec, remap-once and the probe report `18 passed, 0 failed, 3 spec files`.
- In the probe (a record and a document both conflicted in remap's merge-tree):
  - with the mutant: `PROBE remap ok=true`, `c0001.md has conflict markers: true`, and HEAD `Merge origin/main after remap`;
  - unmutated: `remap ok=false`, "remap committed, but merging origin/main conflicts", and no conflict markers.
- Neither promoted fixture can see the mutant. remap.spec's merge conflicts only in the record. remap-once's conflicts only in a document, so no record is collected and the mutant returns nil, as before.

Critique: the old guarantee now runs through a new code path with no case of its own.
Consequences: none beyond the case; the rule carries over to F2's routine.
Recommendation:
- Add a remap.spec case in the probe's shape: remap fails naming the conflict, HEAD is the remap commit, and the tree has no conflict markers.
- Add a Rules row with the mutant "remap accepts a non-record conflict beside a record".

Lesson: zz-test/guard-needs-its-own-case.

### F4 [medium] `mergeRef` treats a merge it did not start as its own. With a hand merge of another branch in progress, `./zn sync` commits that merge and prints "synced" without merging origin/main
Where:
- `mergeRef`'s first lines. `git merge` fails because MERGE_HEAD exists; `rev-parse --verify MERGE_HEAD` then succeeds, so the body runs on the user's merge, with the base taken against that branch.
- `mergeOrigin`'s message: "… commit; ./zn sync does it for the record alone".
- The hand path in zz-rules.

Evidence: run (b) P4.
- The worktree merges a local branch `side` by hand, and only c0040's record conflicts (both sides appended). Main moves on meanwhile.
- `./zn sync` prints `P4 sync ok=true`, then `synced to 63ee0f7`.
- HEAD is `Merge branch 'side' into raft-a`, and `origin/main merged: false`.
- When a conflict outside the records is still unresolved, `mergeRef` runs `git merge --abort` on the user's merge instead, which discards their resolutions (as the old code did).
- The same goes for every command that merges through `mergeOrigin` after it publishes, and for `land`.

Critique:
- The old code failed loudly. This one reports success for a merge it didn't make, and commits one the user had not finished.
- The text printed after a failed sync invites running sync again in the middle of the hand merge.

Consequences:
- Refusing outright means a user half-way through a hand merge of origin/main can't hand the records to the engine.
- Allowing the merge only when MERGE_HEAD is the commit `ref` names keeps that case. Sync fetches first, so a stale hand merge still refuses.
- A cherry-pick (CHERRY_PICK_HEAD), a revert (REVERT_HEAD) or a rebase (`rebase-merge`, `rebase-apply`) in progress needs the same treatment.

Recommendation:
- Before merging, refuse while any of those operations is in progress. The one exception is a merge whose MERGE_HEAD equals `ref`'s commit: finish that one (settle, then commit).
- Never abort a merge `mergeRef` did not start.
- State the rule in Behaviour 5 and zz-rules, and use it in place of "./zn sync does it for the record alone".

record.spec gets two cases:
- (vii) A hand merge of another branch is in progress: the sync refuses, MERGE_HEAD is still that branch, and the worktree is as it was.
- (viii) A hand merge of origin/main has only the record left conflicted: the sync finishes it, with main's rows first.

Mutant: "merge: adopts a merge in progress", which fails (vii).

### F5 [medium] The merge takes any `<id>/provenance.md` anywhere in the tree for the item's record, while publish and audit take only the item's own folder. A sync deletes a sample record from an id-named folder and unites its rows into the real one
Where:
- In `mergeRef`, `note` matches `"/([fdcR]%d%d%d%d)/provenance%.md$"`, and the removal loop matches `` `/{id}/provenance%.md$` ``.
- `provenance.locate` matches `` `(.*/{id})/provenance%.md$` `` and `` `^({id})/provenance%.md$` ``, and provenance.spec pins that with `locate({ "c0019/provenance.md" }, "c0019")`.
- `uniteRemapRecords` matches `/provenance%.md$`.
- By contrast, `publish.allowed` goes through `publish.itemPath` (`<root>/(issues|rafts)/[active/|done/]<id>/<file>`), and audit uses its own scan.

Evidence: run (b) P2.
- Our branch adds `pickman/.tracker/issues/c0011/experiments/split/c0040/provenance.md`, a hand-off sample in the same shape as c0263's own `experiments/split/<id>/`. Main writes c0040's real record, `[Real]`.
- `./zn sync` prints `P2 sync ok=true`, and `P2 sample still there: false`. c0040's record now holds `Real, Sample`.
- `git ls-files | grep -E '/[fdcR][0-9]{4}/' | grep -vE '\.tracker/' | sed -E 's#/[^/]+$##' | sort -u` lists the id-named folders outside the trackers: `pickman/tests/acceptance/c0002`, `c0003`, `c0010` … `d0124`.
- c0263's own `experiments/split/{c0280,c0282,c0283,c0284}` are id-named folders inside an item's folder.
- None of these holds a `provenance.md` today (`git ls-files | grep -i provenance` lists only spec files).

Critique: three readers decide which file is an item's record, and the merge's reader is the widest, and it acts with `git rm`. The tempting fix, excluding `experiments/`, is just another narrow filter.

Consequences: one predicate, `publish.itemPath(path)` with `rel == "provenance.md"`, used by `mergeRef`, `locate` and remap's settling (F2).
- Retired rafts: `itemPath` doesn't accept `rafts/retired/`, but audit's `STATES` includes `retired/`, and `recombine` retires rafts. Decide whether a retired raft's record merges as a record (then `itemPath` learns `retired/` for rafts) or stops as a conflict outside the records.
- provenance.spec's root-level `locate` case changes.

Recommendation:
- Adopt the one predicate.
- record.spec: a case in P2's shape. The sample stays where it is, and c0040's record is exactly main's.
- provenance.spec: `locate` ignores a `provenance.md` outside an item folder.
- Mutant: "locate takes any folder named by the id".

Lesson: zz-arch/one-definition-of-tracker-state, zz-arch/one-reader-per-format.

### F6 [medium] No merge case has a raft's record, which is the case c0250 needs. A mutant that drops `R` from `mergeRef`'s id pattern passes all 22 cases of record.spec, and with it a raft's `done` branch can't sync
Where:
- Behaviour 1 and 2: "a raft's folder too … c0250 blocks whole rafts".
- `mergeRef`'s `note`.
- record.spec: every merge case uses an issue id.

Evidence: run (c).
- The mutant changes `[fdcR]` to `[fdc]` in `note`. With it, record.spec passes 22 of 22.
- The probe, P5: our raft branch moves `rafts/active/R0150` to `done/` (what `done` does), and main publishes an `unblocked` row into the active raft's record.
  - With the mutant, the sync fails: "merging origin/main failed … CONFLICT (file location): pickman/.tracker/rafts/active/R0150/provenance.md …".
  - Unmutated, it prints `synced`, and the row is in `rafts/done/R0150/provenance.md` with no `active/` folder left.

Critique: a whole-raft block is the reason this layer allows records in a raft's folder at all, and the merge path for one has no case.
Consequences: none beyond the case.
Recommendation:
- Add a record.spec case in P5's shape (the UA shape for a raft), using `oneRecordBeside` generalised to rafts.
- Add a Rules row with the mutant "merge: ignores raft records".

Lesson: zz-test/seed-every-enumerated-case.

### F7 [medium] `settle`'s contract is not in the Design
- Its return actions are only in the spec.
- The "kept but left unmerged" stop is in neither.
- The message an id change gets depends on the order of the ids, and neither order names `./zn remap`.
- Two sides that both deleted a record stop as "an id changed".

Where:
- Interfaces: no `settle`, though it says later layers add to the module "without changing what is above".
- Behaviour 5.
- AC6: "a message naming the item (and `./zn remap` for an id change)".
- record.spec (ii), whose needle is "no document".
- `mergeRef`: `table.sort(ids)` and `elseif action == "keep" and unmerged`.

Evidence:
- **The actions.** provenance.spec pins the actions `"keep"`, `"write"` and `"remove"`, but `grep -nE '"keep"|"write"|"remove"|`keep`|`write`|`remove`' c0263.md` finds nothing, and the Interfaces block has no `settle`.
- **An id changed downward.** Run (b) P3: we added a record in c0022, and main renumbered c0022 down to c0002.
  - The sync prints `c0002: left unmerged by git and unchanged by either side`, then git's CONFLICT text and the hand path. That names neither the old id, nor "no document", nor remap.
  - (ii) gets "no document" only because the ids are sorted and c0022 sorts before c0032.
  - An implementation that handles the unmerged ids first fails (ii) while meeting every Design sentence.
- **Both sides deleted it.** Run (d): `settle(one, nil, nil)` returns `nil nil one side changed the record and the other has none under this id (an id changed: …)`. git sees no conflict there, yet the sync stops with a wrong reason.

Critique: a sequestered case pins an order the Design never states, and the message AC6 promises for an id change is never produced.
Consequences: with F1's guard, a compaction (the downward case in practice) is refused before settling. So P3's shape remains only for a renumber whose target was picked by hand.

Recommendation:
- Add `provenance.settle(common, ours, theirs): (("keep" | "write" | "remove")?, string?, string?)` to Interfaces, with its table.
- `settle(common, nil, nil)` returns `"remove"`, with a pure case.
- State the "kept but left unmerged" stop in Behaviour 5, and have its message name the paths git reported, so both ids appear.
- Make (ii) independent of order: either process the ids from the two diffs before the unmerged ones, or use needles that every order prints.
- Make AC6's "and `./zn remap` for an id change" true of (ii), or reword it.

Lesson: z-design/spec-design-correspondence.

### F8 [low] record.spec's per-source loop can't tell a missing row from a repeated actor
Where: record.spec, "./zn record publishes …", the `sources` loop and `lastActor`.
Evidence (read, not run):
- AI_AGENT, ZN_DISPATCH, CURSOR_AGENT and GROK_SESSION_ID, run in that order, all expect `agent:unknown effort unknown`, and `lastActor()` reads origin's last row.
- So an implementation of `record` that exits 0 without publishing under `ZN_DISPATCH` passes the ZN_DISPATCH, CURSOR_AGENT and GROK_SESSION_ID entries on AI_AGENT's row. One plausible misreading leads there: z-design says that under the dispatcher, "the dispatcher pushes that tracker state to `main` for you".

Recommendation: for each source, also expect the number of `ranked` rows on origin to grow by one.
Lesson: zz-test/no-vacuous-pass.

### F9 [low] (partly repeat of design-review-010 F6) Texts that disagree, and a fix the refute claims that isn't in the document
Where and Evidence:
- **Implementation step 1** says "Apply the prototype's patch … as the starting point". `grep -n 3way c0263.md` finds nothing, yet design-refute-010 F6 lists "step 1's `--3way`" as fixed.
  - Run (f): `git apply --check` on origin/main ae926c87 fails with `patch failed: z-nile/README.md:114` and `z-nile/skills/zz-rules/SKILL.md:74`.
  - With `--3way`, it reports "Applied patch to 'z-nile/README.md' with conflicts".
- **Edge cases:** "`renumber` and `compact` rewrite ids in old rows and headers on a branch: Behaviour 5, limit (1)". Behaviour 5 has a single, unnumbered "Limit, stated.", and `compact` runs on main.
- **`mergeOrigin`'s message** ends "commit; ./zn sync does it for the record alone", and it prints that when `./zn sync` itself has just failed (F4).
- **zz-rules' "the same way"** and **check.sh's AC6 label** describe remap's merge as it is not (F2).
- **The Regression guard** says its specs were "(all run on the prototype, below)". E16's round-4 list leaves out some of them:
  - `tooling/{spend,affected,dispatch-texts}`;
  - `c0116/{plan-cli,compact-record}`;
  - `c0114/publish-roots`;
  - `c0070/board-refresh`;
  - `c0082/{audit,cli}`;
  - `c0119/scope-docs`.

  Run (e) ran five of them on e4f0efec (32 passed, 0 failed).

Recommendation:
- Fix each text.
- Make step 1 say `git apply --3way` and to resolve the README hunk by hand, or rebase the patch onto today's main.
- Record run (e) in E16, and name the files still unrun on e4f0efec.

Lesson: z-design/restated-rules-move-together.

Notes (not findings):
- **Round-3 answers checked.**
  - `git rm -f` empties the folder, and the cases assert on the disk and on `./zn find`.
  - The cross-item case (iii) passes for `sync` because the ids come from both diffs.
  - The five stop cases and their mutants are there.
  - The docs needles "unites a `provenance.md` both sides appended" and "`remap` unites a record" each have 0 hits on origin/main.
  - The 65 entries of `mutants.py` are all named in the Rules table (a script compared the two lists).
  - The counts (6, 3, 22, 8) match the files, and `size: 720` matches the patch's 695 added and 24 removed lines.
- **Merge edges that hold.**
  - With several merge bases, one base is used, and a side that doesn't extend it is refused: a safe stop.
  - The ids from one base are complete, because git pairs only into paths a side added.
  - An unmerged path that is not a record stops the merge.
  - An empty, whitespace-only or CRLF record fails `parse`, so the merge stops.
  - An error inside the `pcall` aborts the merge.
  - A fast-forward stays a fast-forward under `--no-commit`.
  - An abort after a write leaves the tree as it was (review 010's AB probe).
  - I found no flaky minute boundary: the rows that must stay distinct have distinct actors or fixed `when`s.
- **`git commit --no-edit`** runs the `pre-commit` and `commit-msg` hooks where `git merge` ran `pre-merge-commit`. The repository installs none, and the fence's stubs delegate to none, so no spec sees the change. A user's own pre-commit hook would now run on every engine merge.
- **Overrides "none": still plausible.** No promoted fixture holds a record, so F1's guard changes no promoted answer. The owed whole-suite run (Implementation step 1) stands, and run (e) adds 32 cases on e4f0efec.
- **Repository safety.**
  - The specs write only `.cache` fixtures and commit as `@example.invalid`.
  - `mutants.py` edits the detached copy `proto-c0263-mut` and restores it.
  - My probes ran in a scratch clone with a throwaway origin; each mutant was restored; the temporary worktree was removed and pruned.
- **Lessons.** The round-4 commit changed no lesson file, and `harvest.md` maps review 010's findings to existing lessons.

Candidate lessons (for the lead):
- **A helper that finishes or aborts a git operation first checks that it started it.** Check: is MERGE_HEAD, CHERRY_PICK_HEAD or a rebase absent before it runs, or is MERGE_HEAD the ref it merges? What does it do when the user is in the middle of merging another branch? (F4)
- **When a mechanism is replaced, its other copies are replaced too.** Check: does `git grep` for the old mechanism's calls (here, conflicted-file stages) find a second caller, and do that caller's cases include the shapes that retired it? (F2)
- **An identity keyed by id holds only within one id scheme.** Check: before settling two commits by id, does the code confirm they share the compaction map? (F1; this would be a note on zz-rules/item-history-spans-moves-and-compaction.)

Verdict: changes
