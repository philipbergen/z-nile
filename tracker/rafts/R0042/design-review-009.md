# Review 009: R0042 (design mode)
Inputs: prep-z-nile at d83c7e4 (R0042.md, check.sh, harvest.md, design-review-006/007/008 and design-refute-006/007/008; c0111 and c0119 documents, check.sh files and acceptance specs). The prototype `.worktree/proto-scope-fidelity`: its c0111 and c0119 acceptance folders are byte-identical to this tree, and its `scripts/tracker/trail.luau`, `cmd.capture` and `cmd.metrics` were read against the Design.
Every round-008 refutation was checked against the tree and the prototype and holds, so no round-008 finding is repeated. Settled user decisions (2026-10-20), including the read-only `tracker.sh capture <id>`, are not reopened. F1 questions the trail mechanism. Rounds 007 F1 and 008 F1 already found holes in it.

Run on the prototype: c0111's and c0119's acceptance specs (`59 passed, 0 failed, 11 spec files`); `luau-lsp analyze --base-luaurc=.luaurc --platform=standard` of both acceptance folders and `scripts` (exit 0); `lessons --check` (`21 lessons, 95 harvest entries, ok`); `--uncovered R0040 R0042` (covered); `capture` over every open item on `origin/main` (31 items), plus c0005. I didn't run `promote-check`. `origin/main` has no merge commits, so the `<cut>..<upper>` spans are exact.

Lessons pass (item 10): I asked each design lesson's `check` of the draft. Failed: `tracker/item-history-spans-moves-and-compaction` and `testing/no-vacuous-pass` (F1). The others pass or don't apply:
- `one-reader-per-format`: `namedIds` matches `tracker.sh new`'s `tracker: new {chosen} {slug}` and make-issue's subject, and the maps go through `ids.parseMap`.
- `seed-every-enumerated-case`: `active/` is pinned by trail.spec's `ranges` equality.
- `pin-call-site-arguments`: `head` and `kind` are pinned by capture-cli, and the metrics reader's `HEAD` by its unpushed fixture commits.

No lesson was added since round 008, so there are none to judge.

Scope fidelity (item 11): I compared each document with the prototype's `capture`.
- c0111 (`ef5a7a5 tracker: new c0111 Skill lessons`): the title is the same, and the Problem has only gained four `Scope decision` lines. The nine captured Solution bullets are verbatim, followed by the "As designed" paragraph. Non-goals changed, but nothing was fenced off that the capture asked for: script checks are still a non-goal, the seed and backfill went to c0112 by decision, and code-review harvesting moved into scope. Every captured outcome has a Design and a criterion: harvest and apply (AC2, AC6), search (AC3, AC4), prompt (AC5), metrics (AC9).
- c0119 (`ab750c0`): it has only gained the "Decided with the user (2026-10-20)" block. Each rule has AC1 or AC2, and the capture command has AC4.

### F1 [medium] The trail learns an item's earlier ids only from compaction maps, but `renumber` also changes ids and writes no map. A renumbered item's capture is then whatever commit renamed it (a prep's rewrite included), printed as if it were the capture
Where: c0111 The trail (`ranges`, `read`); c0119 Design (`tracker.sh capture`); tracker skill, Duplicate ids and Conflicts (`renumber`); lesson `tracker/item-history-spans-moves-and-compaction`
Evidence:
- `cmd.renumber` (main.luau line 1362) moves an item to a new id and rewrites every reference. It never touches `tracker/compaction.txt`, which only `compact` writes (line 1517). The tracker skill makes renumber the routine fix for a duplicate id, and the copy it renumbers is "normally the fresh backlog stub". That stub is already published, with its `tracker: new <old> …` capture on `origin/main`.
- `ranges` reads only the new id's folders across a renumber. The old folder, which holds the capture commit, is never read. `capture` then finds no `tracker: new` commit naming the new id and falls back to `oldestAdd`, which is the commit that made the new folder. For a renumber done on a prep branch, that is the prep PR's squash commit, carrying the prep's text. Item 11, step 5.5 and ready-raft then diff the prepped document against itself and see nothing to flag.
- This happens on the real tree. c0005 was c0040 and was renumbered to c0041 mid-prep, in 947a5c6, after `wip: prep R0020` commits. `capture c0005` prints `capture 947a5c6 tracker/issues/c0041/c0041-worktrees-by-default.md tracker: renumber worktrees issue c0040 -> c0041 …`. c0040's own first add is never read. c0005 is done, so no audit is wrong today, but the path is still the documented one.
- The output never says that the fallback was used. The line has the same shape as a real capture, so "no capture found, used a first add" looks like "checked and clean". Round 007 F1's Recommendation had asked the reviewer to say when the fallback was used, but no text or code does.
- No spec renumbers an item, so no case can see this.

Lesson: tracker/item-history-spans-moves-and-compaction, testing/no-vacuous-pass
Critique: this is the third round in which the trail misses an id change (007: compaction at all; 008: every compaction; now: renumber). The mechanism rebuilds identity from one kind of evidence, maps that only `compact` writes, so every other operation that changes an id is a silent hole. The tempting fix is to add renumber to the walk with some heuristic, such as a commit that deletes one item folder and adds another. That makes the walk guess, and the next id-changing path is again invisible.
Consequences:
- If renumber records what it did, the trail needs no heuristic. But the record can't go in `compaction.txt`: `remap`, `refuseStale` (line 364) and the merge rule all treat that file as "the last compaction" and compare it whole with origin's.
- A separate append-only ledger means each cut's map is the lines that commit added, not the whole file, or an old rename would be applied at a later cut.
- A loud fallback alone fixes the silence, but every pre-c0072 item also falls back (only 66 `tracker: new` subjects exist on `origin/main`), so it has to say what kind of first add it found, or it becomes noise.

Recommendation:
- Make every id change leave evidence that the trail reads.
  - `renumber` appends `<old> <new>` to a new ledger, `tracker/renumbered.txt`.
  - `trail.read` treats each commit that changed that ledger as a cut. Each cut's map is the lines that commit added (`git show <cut> -- tracker/renumbered.txt`, the `+` lines), merged with the compaction cuts in log order.
  - Write this into The trail and the lesson's `check` ("every compaction and every renumber"), and into the tracker skill's renumber text.
- Independently, make the fallback visible. When `capture` uses `oldestAdd`, the first line ends ` (no capture commit: first add)`.
  - When that first-add commit also deletes another item's document of the same kind (a rename the trail could not follow), it prints `capture: <id> was renamed in <sha> by a path the trail does not follow` on stderr.
  - Item 11, 5.5 and ready-raft say that such a baseline goes to the user.
- Spec cases in capture-cli:
  - a published stub `tracker: new c0510 …`;
  - a commit (subject `R0010: prep`) that renumbers it to c0520, rewrites its Problem and appends to `renumbered.txt`;
  - assert that `capture c0520` prints the c0510 capture;
  - a second item renamed without a ledger line, for the warning;
  - a legacy first add, for the ` (no capture commit: first add)` suffix.
- Rows: "renumber cuts ignored", "the whole ledger used as each cut's map", "fallback unmarked", each run on the prototype.
- If you'd rather not change `renumber` in this raft, escalate to the user: (a) the ledger as above (cost: one tracked file, a `renumber` change and two cases); (b) only the loud fallback and warning, which leaves renumbered items to a user check at every ready; (c) a separate chore before c0114 renumbers anything. Each option keeps c0119's outcome.

### F2 [low] Stale text: c0119's Scalability and the prototype's `cmd.capture` comment still describe the old lookup
Where: c0119 `### Scalability` ("The reviewer's extra step is one `git diff` per item document"); prototype `scripts/tracker/main.luau` line 3430 ("whose subject starts `tracker: new <f|d|c>NNNN`")
Evidence: the reviewer's step is now `tracker.sh capture`. That runs `git rev-parse`, one `git log` and one `git show` per compaction commit, one `git log` per range, and a final `git show`. The capture rule is now the span's id in `namedIds`, not any `<f|d|c>NNNN`. An executor copying the prototype's comment would document the round-007 rule.
Recommendation: reword Scalability to "one `tracker.sh capture` per item: a `git log` per id span and a `git show` per compaction (one today)". When the code is written, make the comment above `cmd.capture` match The trail's `capture` bullet.

Verdict: changes
