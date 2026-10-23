# Review 001: c0118 (design mode)
Inputs: `prep-c0118` at 148462b6 (`c0118.md`, `check.sh`, `acceptance/*`); the prototype `proto-c0118` at 84b02d6d (on the c0117 simulation cbeb2657), whose `check.sh` I re-ran (8/8) and whose `./zn board` I ran into the scratchpad (0.52 s, 3.05 MB, `problems` empty); the programme review `scratchpad/programme-review/c0118.md`; `./zn capture c0118` and the item's whole history (973984a1, fb7fd805, ab750c07, 4c2b7474 on main); the c0117 and c0121 documents on this stack; `./zn lessons --when design --full` and `--skill review`.

Scope (item 11): the capture is confirmed (fb7fd805). The Problem and Solution are unchanged. The text added since is two `Decided with the user` lines and the `Scope decision (user, 2026-10-20)` "Split: static board, then server". The server, its live worktree, PR and checks data, and the three actions are correctly c0121's under that split. Every outcome left with c0118 (tabs including z-nile, six columns, cards, raft bands, the 24-hour window adjustable from 1 hour to 30 days, the card's worktree, model and spend, both charts with their own 90-day range open to all history, navigation and Stats) has a Design section and a Checked criterion. No cut. G1–G5, G7 and G8 are reasonable and contradict nothing. G6 is incomplete (F3).

Programme review: F1, F2, F5, F6, F7 and F10 are answered in the Design. F3, F4, F8 (live data), F9 and F11 are server, action or live-data findings, so they belong to c0121 under the split. Their content isn't carried anywhere c0121 will read (F4 below).

### F1 [high] History keeps a reused id's pre-compaction landing, so 13 items are misdated today and 4 backlog items will be misdated forever
Where: §5 "Compaction", `history.apply` (`if item.closed then … return`; the cut covers only an item *first seen* in the cut commit); `history.spec` fixture
Evidence:
- The 2026-10-05 compaction (a38f91f9) renumbered by reusing ids: `R0010 R0001` and `R0100 R0010` (`z-nile/compaction.txt`). Old R0010, "Foundation", landed 2026-09-28T21:03−07:00 (94c053a9). The compaction deleted it and re-added the old R0100, "Ghosts", as R0010.
- `history.parse` already has R0010 closed, so the re-add is "no change". The prototype's real board (my run, `doneFrom`/`doneAt` from the model JSON) dates the current R0010 "Ghosts" at 2026-09-29T04:03 from history. That is Foundation's landing.
- The same holds for every id that was done before the compaction and reused by it. Items with `doneFrom = "history"` and `doneAt` before the compaction instant: `c0010 c0040 c0041 c0050 c0060 c0070 c0080 R0010 R0020` (done, wrong date) and `f0100 f0110 R0030 R0040` (still in the backlog, yet carrying a doneAt).
- When R0030 ("Suite split") lands, `if item.closed then return` keeps 2026-09-30. Its card never enters the done window, and the rounds chart files its rounds in September.
- E1 rechecked only compaction *targets* (c0001, c0042, R0001, R0006), never reused *sources*. The fixture's compaction adds fresh ids (c0090, R0090), never a reused one.
Critique: this is exactly the identity-across-an-id-change defect that zz-rules forbids. The tempting fix is "clear `closed` too in a cut commit". That changes Stats' `closed` and `spells` (c0073 pins them on the real tree), and it still misses the case where the reused id is re-added outside `done/`.
Consequences: a cut must start a new life for every item whose document the cut commit adds or deletes, as `trail.read` does ("a commit that changed the compaction map and the item's document also starts its life"). Taken one step further, this collides with F2: c0114's map *move* sits in the same commit as every tooling item's move, so treating that commit as a cut would wipe every z-nile date.
Recommendation:
- In a cut commit, reset the `doneAt` life (not `closed` or `spells`, which stay Stats' and unchanged) of every item whose document the commit adds or deletes. A later arrival in `done/` then sets `doneAt` afresh, and a re-add straight into `done/` gives nil (the spend fallback).
- Decide the cut set by F2's rule.
- Spec cases:
  - id X done; then a compaction re-adds a different item as X in the backlog; then X lands. `doneAt.X` is the later landing.
  - X done; then a compaction re-adds a different item as X in `done/`. `doneAt.X` is nil.
  - `closed.X` is unchanged in both cases.
- Mutant rows: "the cut resets nothing for already-closed ids" and "the cut resets `closed`".
- Record the real-tree before and after for the 13 ids in E1.
Lesson: zz-rules/item-history-spans-moves-and-compaction

### F2 [medium] The cut counts the c0114 *move* of the compaction map, which on main is the same squash commit that lands R0043
Where: §5 "a commit that changes a compaction map is a cut"; `history.parse` `flushFile` (`isMap[file.path]` under `--no-renames`); against `trail.cuts` (`-M --diff-filter=AM`: "Moving the map (c0114) is not a compaction")
Evidence:
- `git log --no-renames -- z-nile/compaction.txt tracker/compaction.txt` on the prototype lists 8804fad4, c0114's `git mv` of the map, as a change of both map paths. History's rule makes it a cut.
- On the prototype, that move is a separate commit, so nothing visible breaks.
- On main, rafts land as squash merges (29f1ae5b, 61ae82db: one parent, `(#96)`, `(#97)`), and R0042's squash carried its own `done/` moves. R0043's squash will therefore rename the map and move R0043 and c0114 into `done/` in one commit. Both get no history `doneAt` and fall back to their newest spend row, which predates the merge by however long the PR waited.
- The board's history rule now disagrees with `trail`'s, which already settled this case.
Critique: the tempting fix is to hard-code 8804fad4. It isn't on main, and the real squash's sha is unknown.
Consequences: after F1's fix, a cut resets every item it touches. So misreading a map move as a cut becomes a mass reset of every item c0114 moved, not just two misdated cards.
Recommendation:
- Use `trail`'s rule: a cut is a commit that adds or modifies a map's content, read with renames. Either pass `trail.cuts(HEAD)`'s sha set into `history.parse`, or detect a delete-plus-add of identical content in the log.
- Add it to the `v3` cache key's inputs.
- Spec case: one commit moves `tracker/compaction.txt` to `z-nile/compaction.txt` and lands a raft. The raft is dated from history.
- Mutant row: "a map move is a cut".
- Add a Unknowns line naming the squash shape.

### F3 [medium] "Run" means "a branch `<R-id>-…` exists", but `stop` leaves the branch, so a re-readied raft shows as running when nobody launched it
Where: §3 "Launched"; G6; `board.branchOf`
Evidence:
- zz-rules says `stop` "names the raft's branch and PR, which it leaves as they are".
- The main checkout has this case right now: `R0045-narrow-hiscore-adapter-pins` is a local branch, while R0045 was readied (934be1b2) and then stopped (22785f26) and is back to `prepared`.
- If R0045 is readied again, `active` plus that ref gives `run`. The Ready column, the one that says "waiting for z-run", then hides it.
- G6 covers only "a run that died stays in run". It doesn't cover a raft given back and readied again.
- `model.spec`'s refs cover look-alikes and origin, but not a leftover branch.
Critique: the tempting fix is "delete the branch in `stop`". That changes `stop`'s published contract and the z-stop skill, which are outside this issue's Touched list. It also wouldn't clear `origin/` refs that other clones have already fetched.
Consequences: whatever replaces "exists" has to hold in CI too, where there are no worktrees and no dispatcher state, only refs and history.
Recommendation:
- Launched = a `<R-id>-…` ref whose tip commit is newer than the raft's latest arrival in `active/`. `start` makes its empty `tracker: start` commit after `ready`. Both instants come from data the board already reads: `for-each-ref --format=%(refname:short) %(committerdate:unix)` and history's active spell.
- Optionally OR it with a dispatcher state of step z-run.
- Spec case: a raft readied after its branch's last commit is in Ready, and after a newer commit on the branch it is in Run.
- Mutant row: "any existing branch launches".
- Update G6 to say what a stale branch does.

### F4 [medium] The five findings moved to c0121 aren't recorded anywhere c0121's prep will read
Where: Programme review answers F3, F4, F8, F9, F11 ("c0121's prep must take F3's recommendation whole"); `z-nile/.tracker/issues/c0121/c0121.md`
Evidence:
- c0121's document is a stub. Its Problem lists the outcomes and nothing of F3 (the token, the Host and Origin checks, POST with JSON only, no acting on GET, ids validated against the model), F4 (the main-checkout list and `READ_ONLY`), F8 (the `gh` cache and spend read from worktrees), F9 (the injected `serve.start` seams, no port 0) or F11 (the stale-server notice).
- The programme review exists only in a session scratchpad (`git ls-files | grep -i programme` finds nothing), and c0118 names those findings in one line each.
- c0121's prep, by another agent, will start from c0121's document and its capture.
Critique: these were the review's two security and process-lifetime highs. Moving them is right, but a move with no carrier is how a finding is lost. The tempting fix, editing c0121 in this prep PR, puts another item's document in a prep PR.
Consequences: whoever carries them must not narrow c0121's captured scope, only add detail.
Recommendation:
- Carry them durably. Either commit the programme review's moved findings verbatim into c0118's folder (for example `programme-review.md`), with c0121's Solution pointing at it, or have the lead land a capture on c0121 (`./zn land`, Solution detail only) that lists F3, F4, F8, F9 and F11 with their recommendations.
- Change this section's answers to name where each now lives.

### F5 [low] `znBoard.load` doesn't refresh Stats and has no field for PR and checks
Where: §9; `board.render` (Stats is rendered server side into `{{STATS}}` once); `board.html` `load`
Evidence:
- `load(next)` re-renders the projects, the Board and the lists, but `#stats` is static HTML from `statsHtml`. A served page would show Stats frozen at serve start.
- The card's "PR and checks" row is a fixed sentence with no model field.
- Each polled model is about 2.7 MB (issue bodies are 2.3 MB of it).
- `page.spec` checks only that `load` keeps the project and the window. The range and the selected item, which §9 also promises, have no case.
Recommendation:
- State in §9 what c0121 must still add, or make `load(model, statsHtml?)` replace `#stats`.
- Add `pr`/`checks` (nil in static mode) to the Issue and Raft types, so c0121 fills data rather than editing the page.
- Add a case that `load` keeps the range and the selected card.

### F6 [low] The "history unavailable (shallow)" state described in §8 is never reached, and the spend fallback isn't limited to compaction cuts
Where: §5 (the fallback is for "an item first seen in `done/`" in a cut), §8 (undated history); `board.collect` (`issue.state == "done" and not issue.doneAt`); `board.html` (`model.asOf === undefined`)
Evidence:
- In a shallow clone, `asOf` still comes from `git log -1`, so the done column's note never shows.
- `history.read` gives no `doneAt` there, so every done item with spend is dated by its newest row, and the charts are drawn from those dates.
- That contradicts §8's "history unavailable … no done times" and "charts need the git history".
- No spec covers the shallow case.
Recommendation: either write down that the fallback applies to any done item that history leaves undated (and drop §8's shallow text), or gate the fallback and the note on history being present. Add one model case with `hist == nil` and `asOf` set.

### F7 [low] Rules and mutants is missing rows for rules the Design states
Where: Rules and mutants
Evidence: no rows for:
- `boardview.scaled` (the k and M thresholds);
- `rowInstant` reading UTC minutes and bare days;
- tokens split across members (`spend.attribute`);
- a raft's spend fallback from its members' newest row (M25 is the issue's);
- `load` keeping the range and the selected item;
- F1's, F2's and F3's new rules.
Recommendation: add a row and mutant for each, run them as the existing 47 were, and record the outcomes.

Verdict: changes
