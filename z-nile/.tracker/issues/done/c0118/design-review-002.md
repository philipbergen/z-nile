# Review 002: c0118 (design mode)
Inputs: `prep-c0118` at ece68c13 (`c0118.md`, `check.sh`, `acceptance/*`, `harvest.md`, the two lessons it changed); the prototype `proto-c0118` at 9ad9c0d0 (on the c0117 simulation cbeb2657), cloned into the scratchpad; main at 9734bb65 (R0043's squash 05b058ea), cloned, with the prototype's `history.luau` dropped in; c0121's document on origin/main (2fceeb6b); the programme review `scratchpad/programme-review/c0118.md`; `./zn capture c0118`; `./zn lessons --when design --full`.
Dropped from review-001: none. F2 to F7 are fixed as the refute says. F1's three named results hold, but the new rule is wider than the defect (F1 below).

Verified on the real tree (prototype clone, `board.collect(nil, ".")`):
- R0010 is done, 2026-10-03T16:36Z, from spend.
- R0020 is done, 2026-10-02T15:04Z, from spend.
- c0070 is 2026-10-06T17:09Z and c0080 is 2026-10-06T14:11Z, both from history. They landed after the compaction, and the old c0070 and c0080 became c0008 and c0009 (map).
- R0030, R0040, f0100 and f0110 have no date.
- c0114 is 2026-10-21T07:56Z, from history.

R0043's real squash (05b058ea, one parent, which deletes `tracker/compaction.txt` and adds `z-nile/compaction.txt` with identical content):
- I parsed the log up to `05b058ea^` and up to HEAD with the prototype's reader. The two differ only in R0043 and c0114, both `doneAt` 2026-10-23T23:41:48Z (the squash), `activeAt` 21:16:40Z.
- All 64 other `doneAt` and `activeAt` values are unchanged.
- `isCut` reads the move as no compaction, as designed.

Attacks that found nothing:
- **A renumber.** It never writes the map (`ids.MAP_FILE` is written only by `compact` and `remap`), and it takes a fresh id from the counter. Its delete-plus-add is an ordinary new life, so a compaction followed by a renumber needs no new rule.
- **Ready, stop, ready.**
  - The fixture's R0060 pins `activeAt` at the second ready.
  - R0045 on main has this exact shape. Its branch tip is b7a027a2 (2026-10-21T22:23:42−07:00), a main commit that `./zn worktree` branched from after the ready (21:27:40) and that never got a `start` commit. On a second ready it reads as ready.
- **The same second.** A tip in the ready's own second reads as ready (strictly later; M52). The only realistic way to get it is a worktree cut from an `origin/main` whose tip is the ready commit itself, and that raft really hasn't started.
- **Clock skew.** `ready` commits through `commit-tree` on the machine that runs it, and `start` commits on the same machine. The board compares only commit times, never a wall clock, and CI reads the same commits. No skew is reachable short of two machines.
- **G1 to G8, G6 as updated:** reasonable, and they contradict nothing.
- **Scope (item 11):** the capture is confirmed (fb7fd805). Since round 1 the text gained only detail, plus the moved-outcomes Non-goal backed by the Scope decision. No cut.

### F1 [medium] A compaction resets the dates of every document it rewrites, including ids it keeps for the same item, so the next compaction will undate correctly dated landings
Where: §5 "A compaction ends the dated life of every item whose document it touches, added, deleted or changed"; `history.luau` `date(…, cut)`; the lesson note added to `tracker/item-history-spans-moves-and-compaction` ("ends the dated life of every item whose document it touches, however git shows the change")
Evidence:
- `compact.apply` renumbers items and then rewrites ids in every `.md` and `.sh` under every root (`rewritesIds`). An item that keeps its id but whose document names a renumbered id (`depends_on`, `raft:`, body text) shows as `M` in the compaction commit.
- Under the new rule, that document's `doneAt` and `activeAt` are cleared, although the map says its id still names the same item.
- In the 2026-10-05 compaction this case didn't occur: its 7 in-place `M` item documents (c0010 c0040 c0041 c0050 c0060 R0010 R0020) are all reused targets. That's why E1 looks clean.
- A second `compact` on today's tree would keep the dense low ids (about 0001–0084 and R0001–R0028) and renumber the rest. On the prototype tree, a grep finds 17 done documents with ids it would keep that name ids it would renumber, so their documents would be rewritten: c0045 c0052 c0063 c0064 c0067 c0069 c0076 c0078 c0081 c0084 f0014 f0025 f0026 f0031 R0011 R0025 R0026. (This is an approximation of `compact`'s numbering.)
- Each of those 17 loses its history landing. It falls back to its newest spend row, or is undated and leaves the done column and every chart when it has no rows (pre-ledger items such as c0040 have none).
- `activeAt` is cleared the same way. §3 then treats "no `activeAt`" like a shallow clone ("any such branch counts"), so an active raft whose document the compaction rewrote shows a branch left over from a `stop` as run. That is F3 of round 1 again, through a compaction.
- The fixture's compaction touches only added, deleted and reused documents. No case has a kept id rewritten in place, so nothing pins either behaviour (testing/seed-every-enumerated-case).
Critique: round 1 found the rule too narrow, and this round finds it too wide. The mechanism, "which documents the commit touched", is the wrong signal for "which ids changed meaning". The answer is already in the same diff: the map. The tempting fix is to exempt `M` documents. That brings back round 1's R0010 defect, because a reused id at the same path is also an `M`.
Consequences: deciding from the map means reading the map's pairs at each compaction commit.
- With `--unified=0`, a changed map's `+` lines are only the lines that differ from the old map. A pair the new map shares verbatim with the old one is missing, but such a pair changes no identity either. A newly added map shows every line.
- An id that appears on either side of a pair (`X→Y` with Y≠X, or `W→X` with W≠X) changes meaning.
- A touched document whose id is on no side of any pair keeps its life.
- A map line that doesn't parse should fall back to today's wide reset for that commit (guard-no-is-explicit: an unreadable map means "reset").
- The lesson note this prep added states the wide rule, so it must be reworded too (restated-rules-move-together).
- The same over-reset exists in `trail.read`. That is outside this issue's Touched list, so it isn't this issue's to fix, but §5's "trail.read reads it so too" shouldn't be offered as support.
Recommendation:
- In a compaction commit, end the dated life only of ids named on either side of a changed pair in the map lines the commit adds. Keep the wide reset when a map line doesn't parse.
- Reword §5 and the lesson note to match.
- Spec cases (history.spec):
  - a compaction maps `c0031→c0030` and also rewrites done c0010's document in place (a `depends_on` line). `doneAt.c0010` keeps its landing, and `c0030` still resets.
  - The same for an active raft: `activeAt` survives a rewrite in place.
  - A map line that doesn't parse resets every touched id.
- Mutant rows: "every touched document resets" (the current rule) and "only added and deleted documents reset" (round 1's R0010).
- Rerun E1. It should not change, since all 7 `M` documents were reused ids.
Lesson: testing/seed-every-enumerated-case

### F2 [low] Three places still describe the round-1 design
Where: §1 module table ("cache key `v3`") and Implementation step 2 ("cache key `v3`"), against §2, §5 and the code (`v4`); §10 (`git for-each-ref --format=%(refname:short)`), against §3 and `board.luau:645` (`%(committerdate:unix) %(refname:short)`); AC4's statement ("`znBoard.load` keeps the project and window") and AC2's ("first arrival in `done/`"), neither of which names what the specs now also pin (`load` keeps the range and selection and replaces Stats; `activeAt`)
Evidence: an executor following step 2 writes `v3`. A `v3` cache from a pre-review prototype run then has no `activeAt`, and every active raft with any branch launches. An executor following §10 drops the commit times that §3's launch rule needs.
Recommendation: make §1 and step 2 say `v4`, make §10 quote §3's format, and extend AC2's and AC4's statements to what their specs check (ticket-prep/spec-design-correspondence; restated-rules-move-together).

### F3 [low] c0121's Problem carries the five findings, but drops three of F9's details
Where: c0121.md on origin/main, the F9 bullet; against the programme review's F9 Recommendation
Evidence: carried in full:
- F3: every guard and all five spec cases;
- F4: the allowed list, `READ_ONLY` and the `tracker-guarded` pin;
- F8: the cache, the background refresh, worktree spend and both cases;
- F11.
F9 is missing three details:
- "the page's JS is tested with the c0042 node harness, with `fetch` stubbed";
- "stop it in a final case";
- "repository-safety review checks that no stub spawns a real process outside `.cache`".
F4's "escalate if c0117 lands without stop and retry" is moot now that c0117 exports them, so leaving it out is fine.
Recommendation: at the next capture `land` on c0121, add the three missing F9 details word for word. Nothing in c0118 changes.

Verdict: changes
