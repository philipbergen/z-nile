# Review 010: c0263 (design mode)
Inputs: prep `prep-ticket-provenance` at 1ae4ec61: `c0263.md`, `check.sh`, `acceptance/{provenance,publish,record}.spec.luau`, `experiments/{proto.patch,mutants.py,folder-move.sh}`, `design-review-008.md`/`design-refute-008.md`, `design-review-009.md`/`design-refute-009.md`, `harvest.md`. Prototype `proto-c0263-raft` at 33a05083: `git diff 0ea4a484 33a05083 -- z-nile/engine z-nile/README.md z-nile/skills` is byte-identical to `experiments/proto.patch`, and its three spec copies are byte-identical to the sequestered ones. origin/main 47e6d0d8. Reviews 003 to 007 were read for history only.
Dropped from review-009: F1, F2, F3 (except remap, F3 here), F4, F5 (each fix read; the reorder and multiset cases checked against their mutants by reading). F6 is repeated in part in F6 here, and its renumber-limit part is superseded by F2 here.
Capture: `./zn capture c0263` prints `(no capture commit: first add)`, so it is not a confirmed capture. Judged from history: the Problem is unchanged apart from its dated decision lines, and round 009's scope reading stands.
Runs, every probe through `./zn run --time`, never in the real repository:
- (a) A probe spec, `probe010.spec.luau`, in a scratch clone of 33a05083 under the session scratchpad, whose `origin` points at a throwaway bare copy. It drives the prototype's `./zn sync` in a trackerfix fixture through five shapes: UD, DU, an id changed on main, a record added in a folder main renumbered, and two records where the second aborts. Result: `7 passed`, with the observations printed (F1, F2).
- (b) `crosspair.sh`, plain git in a scratch repository: one item's record paired with another item's new record (F2).
- (c) `udrm.sh`, plain git: what `git rm --cached` plus an unlink leaves in the UD shape, against `git rm -f` (F1).
- (d) `git apply --check` of `proto.patch`, with and without `--3way`, in a worktree of origin/main (F6). `git show origin/main:` greps for the docs needles (F5) and for the texts the design changes (Notes).

### F1 [high] In the UD shape a successful `./zn sync` leaves the item's old folder on disk. Every later engine command on the item then fails with "duplicate id", and `./zn audit` fails. The UD case can't see it: it checks the index and `git status`
Where:
- Behaviour 5: "removes every other path of that id's record".
- AC6: "one record beside the document, nothing at the old path".
- Prototype `main.luau:436-438`: `git rm -q -f --cached --ignore-unmatch`, then `fs.removeFile(path)`.
- record.spec's UD case: `oneRecordBeside` asserts `ls-files` and `status --porcelain`, and neither shows an empty folder.

Evidence: run (a), UD. The base holds c0016's record with one row, and ours appends one. Main publishes three rows, then moves the folder to `active/`.
- The sync reports `UD sync ok=true`, and then `UD old folder on disk: true`.
- `./zn audit` reports `error duplicate pickman/.tracker/issues/active/c0016: the same id is also at pickman/.tracker/issues/c0016` and `error no-document pickman/.tracker/issues/c0016: no c0016.md`. Its `raftless-active` line is the fixture's, as in record.spec.
- `./zn find c0016` fails: `tracker find: duplicate id c0016: pickman/.tracker/issues/c0016, pickman/.tracker/issues/active/c0016`.

How it happens: git leaves our modified record at the old path ("Version HEAD … left in tree"), so the folder exists again. `mergeRef` unlinks the file but not the folder. `store.find` (`store.luau:72-80`) and `audit.scan` take any folder named by an id as the item. (DU left no folder in the same run.)

Run (c): in the same UD shape, `git rm -f` (no `--cached`) leaves `old folder gone`, and `--cached` plus an unlink leaves `old folder left`.
Critique: the command says it synced and `git status` is clean, yet the item is broken for the engine: `status`, `ready`, `done`, `find`, the gate's audit. The UD case exists to pin "nothing at the old path", but it looks only where an empty folder cannot show. The tempting fix, `fs.removeDir` of the parent, must not remove a folder that still holds a file, and must stop at the state folder.
Consequences: `git rm -f -- <path>` removes the file and the folders it empties, and nothing else. A folder that still holds an ignored or untracked file stays, as it does after any folder move today; that is not this layer's.
Recommendation:
- Remove each stale record with `git rm -q -f --ignore-unmatch -- <path>`, with no `--cached` and no unlink.
- In record.spec's UD, DU and UA cases, assert that the old folder is gone on disk (`fs.isDir`) and that `./zn find <id>` names the new folder. Prefer `find` to `audit` here, because the fixture's raftless active item trips audit.
- Add a Rules row with the mutant "merge: stale record unlinked, folder kept" (today's two lines).

Lesson: z-design/spec-design-correspondence

### F2 [high] `mergeRef` examines only the ids git reports as unmerged, and reads each side under that id. A record that git pairs under another id is lost or misplaced, silently: an id changed on one side drops the other side's rows, and git cleanly merges our row into another item's record. The renumber limit says the opposite
Where:
- Behaviour 5 ("finds each record by its item id"; "Limits, stated" (1)).
- design-review-009 F1, Consequence (d): an id that changed "stays the stated limit and aborts".
- Edge cases, last bullet; zz-rules Provenance ("after a `renumber`, also rename its header").
- Prototype `main.luau:340`: a clean merge returns at once. `:360`: the ids come only from `ls-files -u`. `:418-427`: one side present and no base, so that side is taken as the result.

Evidence:
- **An id changed on main.** Run (a), ID. The base holds c0050's record (Base), and ours appends `Ours`. Main renames c0050 to c0045 (folder, document and id text, as `renumber` or `compact` does) and appends `Main`. `./zn sync` prints `synced to ead986b` and HEAD moves. The record at c0045 holds `Base` and `Main`: **`Ours` is gone**, and nothing remains at c0050. Git reported the conflict at `c0045/provenance.md` with our blob as stage 2. `mergeRef` asked HEAD for c0045's record (none) and the base for c0045's (none), so it took theirs.
- **The mirror** (by reading the code): our branch renumbers an item that both sides appended to. Stage 3 lands at our new id, MERGE_HEAD has no record under it, so ours is taken and main's rows are dropped.
- **A renumbered folder.** Run (a), RN. Our branch added a record in c0060, and main renamed c0060 to c0046. The sync aborts with `c0046: a side of the merge deleted the record`, but nobody deleted it. Limit (1) says this case "merges it with a header that names the old id, which `audit` then refuses".
- **Another item's record.** Run (b), plain git. The base's c0016 record is the header plus `| 2026-11-08 10:00 | confirmed | human:Ann |  |`, and ours appends a row. Main appends three rows to c0016 and creates c0017's record with that same row (the same human confirmed both in one minute), then moves c0016 (`ready`). `git merge` exits 0 and reports `rename i/{c0016 => c0017}/provenance.md (88%)`. Our row lands in c0017's record, and c0016's record lacks it.
  - Why git does this: a record is four fixed lines plus short rows, so two items' records that share one row are over 80% alike. Rows written for several items at once (a batch of confirmations, the rafted rows of one rafting PR in c0282) make a shared row likely.
  - `mergeRef` returns at `:340` without looking, and audit finds nothing, because the header names its folder.

Critique: this is the third round in which the merge mechanism has a hole: 008 F3 and F5, 009 F1, and F1 and this finding here. Round 009 moved from git's per-path shapes to the item's id, but `mergeRef` still lets git decide which ids are involved: only the unmerged paths, only on a failed merge. It also reads "not under this id in that commit" as "this side never had it". Git pairs files by content similarity, and records are small, templated files, so git pairs across ids both when an id changes and when two items share a row. The tempting fix is to check each unmerged stage's blob against the commit's record. That catches the id change and the false "deleted", and leaves the clean cross-item merge untouched.
Consequences: questioning the mechanism means `mergeRef` must see every record that either side changed, on clean merges too:
- Merge with `git merge --no-edit --no-commit <ref>`. A fast-forward stays as it is, since our side changed nothing.
- The ids are every `*/provenance.md` path in `git diff --name-only --no-renames <base> HEAD` and `<base> MERGE_HEAD`, old and new paths alike.
- For each id, read each commit's record by id (`locate`):
  - unchanged on one side: take the other side's version, absence included;
  - changed on both sides: `union`;
  - changed on one side and absent on the other (deleted, or its id changed): abort, naming the id, with "after a compaction run `./zn remap`; after a renumber merge by hand". This replaces the false "deleted" text.
- Write the result beside the id's document in the merged index (nothing, when the result is absent). Remove every other path of the id with `git rm -f` (F1), then commit.
- What this costs:
  - two `git diff --name-only` per merge;
  - every merge commit is made by `git commit --no-edit` instead of by `git merge`, with the same message;
  - an engine error between the merge and the commit must abort the merge (a `pcall` around the body).
- A compaction reuses ids for other items. Across one, a by-id comparison either takes the right side or `union` refuses (the base rows are not a prefix), so the sync stops. `remap` is the way through (F3).
- When the branch has several merge bases with main, `merge-base` picks one, and a side that doesn't extend it is refused. That is a safe stop.

Recommendation: adopt the mechanism above, and rewrite Behaviour 5, E14 and Limit (1) to match: a changed id stops the sync and names it.

record.spec gets these cases:
- (i) Main renumbers an item that both sides appended to. The sync stops with the tree as it was, and the message names the id and `remap`.
- (ii) The RN shape. The sync stops with that message, not "deleted".
- (iii) The cross-item shape, with rows written through `f.other` with fixed `when` values. (`./zn record` stamps the current minute, so a pair of its rows can straddle a minute and make the case flaky.) The sync leaves our row in the moved item's record, beside its document, and leaves the other item's record without it.
- (iv) Our side renumbers (the mirror of (i)).

Add Rules rows for these mutants:
- "merge examines only unmerged ids" (today's code), which fails (iii);
- "a record changed on one side and absent on the other is taken as one-sided", which fails (i) and (iv);
- "a clean merge skips the records", which fails (iii).

Lesson: zz-rules/item-history-spans-moves-and-compaction (never infer identity across an id change), z-design/histories-checked-against-a-real-life

### F3 [medium] The remap Open point is a fair question for the user, but its premise misquotes the capture, and the design takes the narrower answer while the question is open, which z-design forbids. Limit (2) and zz-rules state that answer as settled
Where: Open points 1; Behaviour 5, Limit (2); the last sentence of zz-rules' Provenance section; design-refute-009 F3; `z-nile/skills/z-design/SKILL.md:65`.
Evidence:
- The Open point says "The captured outcome names the engine's merges of `origin/main` … so it was left out". `./zn capture c0263` names no merge: the merges are prep detail and AC6's wording. What the user kept in c0263 is the Scope decision's "the union of two writers", and remap's merge is one of the engine's merges of `origin/main`, so option (b) narrows it.
- "This design does (b) until the user decides." z-design:65 says: "If the only fix you see removes, defers or shrinks an outcome …, ask the user before you answer it … Without that line, the answer is a redesign that keeps the outcome."
- After F2's fix, `remap` is the only way through a compaction for a branch whose record both sides appended to. Under (b), every such branch merges by hand.

Critique: the question is honest; the default is not. Approved as written, the issue would go to `design: ready` with a user question it has already answered the narrow way.
Consequences: (a) touches remap's `merge-tree` path and its fixture (`tooling/remap-once`). (b) needs a dated line.
Recommendation: escalate to the user:
- (a) Unite records in `remap`: read the three stages from `merge-tree --write-tree`'s conflicted-file info, and write the union into the tree with mktree. That is about 30 lines, a case (in record.spec or remap-once's fixture) and the mutant "remap skips the union".
- (b) Keep the limit, with a `Decided with the user` line.

Until one is recorded, the issue is not set `design: ready`. Reword the premise (the outcome is the Scope decision's union of two writers, not a captured list of merges), and put F2's interplay in the question.
Lesson: z-design/never-narrow-captured-scope

### F4 [medium] `mergeRef`'s stated stops have no case: two records of one id in one commit, no document in the merge, two documents. Two plausible mutants survive, and one of them crashes in the middle of the merge
Where: Behaviour 5 ("the same id in two places in one commit aborts"; "no document, or two, aborts"); prototype `main.luau:390-392` (the `why` from `locate`), `:399-412`; the Rules table (the `locate` row pins only the pure function).
Evidence (read, not run): no record.spec case has a commit holding two records of one id, or a merged index without the item's document, or with two. `locate takes the first of two` is killed by the pure case alone.
- Mutant `local why = nil` (`mergeRef` ignores `locate`'s refusal, so `recordAt` reads that side as having no record): no case reaches it.
- Mutant deleting the `if not docFolder then return abort(…)` block: `target` becomes `nil/provenance.md`, `fs.writeFile` throws, and the engine dies in the middle of the merge with `MERGE_HEAD` left. No case reaches it either.

Critique: a stop that only the adapter enforces, with no case that hands it that input, passes with the stop deleted.
Consequences: none beyond the cases. These stops remain under F2's mechanism.
Recommendation: add record.spec cases, each asserting the tree as it was and the message:
- (i) Main deletes an item's folder (`git rm -r`) while ours appended to its record: the sync stops, naming the item.
- (ii) Ours copies an item's record into `active/<id>/` (so HEAD holds two) while both sides append: the sync stops, naming both paths.
- (iii) Ours adds only a copy of the document in another state folder while both sides append: the sync stops on two documents.

Add Rules rows for the two mutants above.
Lesson: z-design/spec-design-correspondence, zz-test/pin-fail-safes-where-they-act

### F5 [medium] AC7's zz-execute needle is already on origin/main, so AC7's "zz-execute's Phase 5 says `./zn sync`" passes with Phase 5 unchanged
Where: `provenance.spec:351` (`has("z-nile/skills/zz-execute/SKILL.md", "./zn sync")`); AC7; the docs Rules row ("phrases only the new text has", `reasoned`).
Evidence:
- `git show origin/main:z-nile/skills/zz-execute/SKILL.md | grep -c -F './zn sync'` gives `2`: lines 14 and 15, the worktree and `start` steps.
- An implementation that leaves Phase 5 step 2 as "`git fetch origin main` and merge it into the branch now" passes the docs case.
- Every other needle has 0 hits on origin/main. In zz-rules: `provenance.md`, `./zn record`, `ZN_ACTOR`, `--actor`, `CLAUDECODE`, `AI_AGENT`, `ZN_DISPATCH`, `CURSOR_AGENT`, `GROK_SESSION_ID`, `merge by hand`. In the README: `provenance`.

Critique: the promoted pin holds nothing, and Phase 5 step 2 is exactly the text that review-009 F3 found disagreeing with the rule.
Consequences: none.
Recommendation: pin a phrase only the new step has, such as "unites a `provenance.md` both sides appended". Or find the step-2 line (by "so the PR is up to date before `done`") and assert that it holds `./zn sync` and not "`git fetch origin main` and merge". Then the docs row can name a mutant (step 2 reverted) and be `run`.
Lesson: zz-test/no-vacuous-pass

### F6 [low] (partly repeat of design-review-009 F6) Texts that disagree, and refuted fixes that aren't in the document
Where and Evidence:
- **Case count.** Affected specs says `record.spec.luau (14)`, but the file and E15 have 15.
- **The live actor.** The Solution says "when `CLAUDECODE` or `AI_AGENT` is set and non-empty". Behaviour 1 and 2, AC1, zz-rules and `hint` name five variables, and the comment at `provenance.spec:78` names three.
- **Implementation step 1.** design-refute-009 F6 says "step 1 says `git apply --3way` and to rebase on a moved README". Step 1 says neither: `grep -n 3way c0263.md` finds nothing. Run (d): `git apply --check` fails on origin/main 47e6d0d8 (`patch failed: z-nile/README.md:114`, and `z-nile/skills/zz-rules/SKILL.md:74`). With `--3way` the README applies "with conflicts" and the rest applies cleanly.
- **E16.** It records the promoted runs on the first prototype and on the one "after round 1" (507efe0e). Round 2 replaced `mergeRef` (b1b53559 to 33a05083), and no run on 33a05083 is recorded.
- **Test plan.** AC6 omits the fifteenth case ("a record one side deleted and the other changed").
- **E5.** The record of the `grok -p` probe does not say that it ran through `./zn run --time`.
- **zz-rules Provenance** says `land`, `fold` and `recombine` merge for you. Behaviour 5 also names `new raft`, and every publishing command through `mergeOrigin`.
- **Limit (1)** describes what does not happen (F2).

Recommendation:
- Fix each text.
- Record the 33a05083 run in E16 (its spec files and case counts).
- Make step 1 say `git apply --3way` and to resolve the README hunk by hand, or rebase the patch onto today's main.

Lesson: z-design/restated-rules-move-together

Notes (not findings):
- **Round-2 answers checked.**
  - The reorder cases: in provenance.spec, `appendOnly`, `publishProblem` and `union` on either side; in publish.spec, origin's two rows swapped and a third appended.
  - The multiset counts {2,1}, {1,2} and {2,2}, each against its mutant, by reading.
  - `CURSOR_AGENT` and `GROK_SESSION_ID` in `hint`, `liveActor`, `HUMAN` and the needles.
  - The hand path, pinned in record.spec (`git merge origin/main`, `origin/main's new rows`).
  - All 57 entry names in `mutants.py` appear in the Rules table (a script compared the two lists).
- **Merge edges that hold.**
  - An abort after a first record was already united leaves the tree as it was. Run (a), AB, reported `HEAD same: true`, an empty status and no `MERGE_HEAD`. (Its message, "deleted the record", is correct there.)
  - DU leaves no folder.
  - An unmerged document stops the sync (record.spec).
  - Both sides deleting a record is no conflict.
  - With several merge bases, one base is used, and a side that doesn't extend it is refused: a safe stop.
- **Overrides "none": plausible.** `git grep` on origin/main's tests for the texts the design changes ("plain `git`", "merge it into the branch", "resolve it with", "published, but merging", "merge `origin/main` and retry", "merging origin/main failed", "git merge origin/main") finds only two:
  - `tooling/remap-once:127`, remap's own message, which is kept;
  - `c0052/skill-doc`'s "git fetch origin main", on the Conflicts line, which is unchanged.

  F2's mechanism makes every merge `--no-commit` followed by a commit, so the owed whole-suite run (step 1) must come after that change.
- **Repository safety.** The specs write only `.cache` fixtures, committing as `@example.invalid`. `mutants.py` edits a detached copy (`proto-c0263-mut`) and restores it. My probes ran in a scratch clone with a throwaway origin, and in scratch repositories.
- **Lessons.** No lesson file changed on the prep branch since round 009. `harvest.md` maps that round's findings to existing lessons.

Candidate lessons (for the lead):
- A merge helper that acts only on what git reports as conflicted trusts git's pairing of small, templated files. Git pairs across items both when an id changes and when two records share a row. Check: does the helper examine every record either side changed, on clean merges too? Does a case put a near-identical record of another item beside the moved one?
- A removal made during a merge must remove the folder it empties. Check: does the case for "nothing at the old place" read the disk the way the engine does (a folder scan), not only the index or `git status`?

Verdict: changes
