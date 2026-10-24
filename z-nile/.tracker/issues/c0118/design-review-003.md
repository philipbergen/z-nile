# Review 003: c0118 (design mode)
Inputs: `prep-c0118` at 266e8c90 (`c0118.md`, `check.sh`, `acceptance/history.spec.luau`, the lesson `tracker/item-history-spans-moves-and-compaction`); the prototype `proto-c0118` at 8c5e31f0, cloned into the scratchpad (diff against round 2's 9ad9c0d0: `history.luau`, `board.luau`, the history spec, `c0118.md`); `ids.parseMap`, `ids.plan`, `ids.formatMap` and `compact` in `main.luau`; `./zn capture c0118`.
Dropped from review-002: none. F1, F2 and F3 are fixed as the refute says. F1's new rule is right, but one side of it is unpinned (F1 below).

Verified:
- **Kept ids keep their dates.** The spec's in-place rewrites of done c0010 and active R0060 keep `doneAt` and `activeAt`.
- **Reused ids are undated.** R0050, reused at the same path, is undated.
- **Unparsable map line.** It takes the wide reset with one warning, and `board.collect` adds that warning to `problems`.
- **Specs and mutants.** Both history specs pass (18 cases). Spot-run mutants: M64 is killed. "Only the old side counts" is killed (3 failures).
- **E1 on the real tree** (clone, full history, roots `pickman/.tracker,z-nile/.tracker,tracker`):
  - The map rule and round 2's wide rule give byte-identical `doneAt` and `activeAt` (72 entries), with 0 warnings.
  - c0070 is 2026-10-06T17:09Z, c0080 is 2026-10-06T14:11Z and c0114 is 2026-10-21T07:56Z.
  - R0010, R0020, R0030, R0040, f0100 and f0110 have no history date, as in round 2.
- **Attacks on the rule** (`history.parse` on handwritten logs):
  - **X→Y where Y was a done item.** It doesn't matter whether Y's old document was dropped earlier or is rewritten in place: Y is undated, and X is gone.
  - **The chain c0003→c0002, c0002→c0001.** All three are undated. The kept c0004, rewritten in place, keeps its landing.
  - **A duplicate map line.** `parseMap` refuses it, so every touched item is undated with one warning. A harmless duplicate thus fails closed and visibly, which is right for a file that `compact` writes.
- **No regression.** The fix delta touches only `history.luau` (the map rule, `warnings`, cache key `v5`) and the five lines in `board.luau` that pass warnings into `problems`. A `v4` cache is refused by its key.
- **G1–G8.** Each is now a "Decided with the user (2026-10-23)" line with the answer quoted. The guess list became "Decisions", and §2, §3 and §5 cite them. The capture (fb7fd805) is unchanged in scope.

### F1 [medium] Nothing pins the old side of a pair: the mutant "only the new id resets" passes every spec, and on the real tree it misdates R0030 and R0040
Where: `history.luau` `renamedIds` (`out[old] = true`); `acceptance/history.spec.luau`; the Rules and mutants table, rows M62–M65
Evidence:
- **The mutant.** I deleted `out[old] = true`. The c0118 history, model and real specs and c0073's history spec all still pass (24 of 24).
- **Handwritten log.** c0005 is done on 2026-10-01. A compaction maps `c0005 c0002`, and a new c0005 lands on 2026-10-12. The real code dates c0005 2026-10-12, and the mutant dates it 2026-10-01.
  - The deleted document leaves `doneAt` set.
  - On the re-arrival, `date`'s `item.doneAt == nil` guard keeps the old life's landing.
- **This is the common case.** `ids.plan` renumbers densely, so every old id above the new count is on the old side only, and the counter hands those ids out again.
- **On the real log** the mutant emits 92 stale `doneAt` values, among them R0030 and R0040. Both are backlog rafts on the tree today. When either lands, it would show the old 2026-10 raft's date.
Critique: the rule has two halves, and the spec seeds only cases where the old id is also some pair's new id, or never comes back. The tempting fix, "add a case where X is reused", is right, but it must be the counter's reuse, not another compaction's.
Consequences: none beyond one fixture commit and one mutant row.
Recommendation:
- Add a history.spec case. A compaction maps `cX cY`, where cX is on no pair's right side. A later commit adds a new cX to `done/`. Then `doneAt.cX` is that later commit, and it is unset before that commit.
- Add the same case for `activeAt`, with a raft id reallocated into `active/`.
- Add mutant M66, "only the new side of a pair resets", run and killed.

### F2 [low] `--unified=0` drops a map pair that repeats verbatim from the previous map, but `compact` rewrites the whole map for each compaction, so a repeated pair can still change an id's meaning
Where: `history.luau` `renamedIds` ("from the lines each added or changed map adds"); review-002 F1's Consequences ("such a pair changes no identity either"). That premise was mine, and it is wrong: `compact` calls `fs.writeFile(MAP_FILE, formatMap(map, …))` with that compaction's map only.
Evidence: handwritten log.
- Compaction 1 maps `c0005 c0002`.
- The old c0002 is later removed, and a new c0005 lands on 2026-10-06.
- Compaction 2's map again holds `c0005 c0002`, under a new header. Its `+` lines are the header alone, so nothing is renamed.
- c0002 gets compaction 2's own instant (2026-10-09) as its landing: round 1's squash-date defect.

Reaching it requires the counter to come back to X and enough removals for X to rank exactly Y again. That is remote, hence low.
Recommendation:
- Judge a compaction by the whole map it leaves, not by its diff. For the few commits that `isCut` flags, read the map with `git show <sha>:<map>`; that needs `%H` in the log format and is a second read only at compactions. Alternatively, rebuild the map's content from the hunks.
- Add a spec case: two compactions whose maps share a pair X≠Y, and the second one's target is undated.
- If the author keeps the diff instead, state the assumption, with its reason, in §5 and the lesson note.

Verdict: changes
