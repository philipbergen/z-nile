# Refute 002: c0118 (answers to design-review-002)
The prototype `proto-c0118` is amended. The prep folder's `prototype.patch`, specs and `c0118.md` follow it.

- F1: fixed: a compaction now undates only the ids named on either side of a pair (X ≠ Y) in the map lines it adds. The lines are read with `ids.parseMap`, the map's one reader, from each added or changed map's `+` lines.
  - An id the compaction keeps keeps its `doneAt` and `activeAt`, even when its document is rewritten in place.
  - When a map line doesn't parse, every touched item is reset and `Parsed.warnings` names the commit; the board adds it to `problems`.
  - §5, §1, Implementation step 2 and the lesson note now state the map rule, and §5 no longer cites `trail.read`.
  - New `history.spec` cases, in the same compaction commit:
    - done c0010's document is rewritten in place, and c0010 keeps its landing;
    - active R0060's document is rewritten in place, and R0060 keeps its `activeAt`;
    - a later commit adds a map line that doesn't parse and rewrites c0040, which loses its landing, with one warning.
  - The fixture's map now names R0050, the id reused at the same path. The older map names R0070, so a map move misread as a compaction would undate R0070's squashed landing; that keeps M50 meaningful under the new rule.
  - New mutants:
    - M62, every touched document resets (the review-001 rule);
    - M63, only added and deleted documents reset (the round-1 rule);
    - M64, an unparsable map resets nothing;
    - M65, no warning.
  - All four are killed, along with every other history mutant, rerun after the fixture change.
  - E1 rerun on the real tree: unchanged, since the 7 in-place documents of 2026-10-05 were all reused ids.
  - The cache key is now `v5`.
  - Consequences: `trail.read` keeps its wider reset. It is outside this issue's Touched modules and only marks capture history, so no new issue is needed for c0118's outcomes. The reviewer named it; I'm passing it to the lead as a possible follow-up.
- F2: fixed:
  - §1 and Implementation step 2 say `v5`.
  - §10 quotes §3's format, `%(committerdate:unix) %(refname:short)`.
  - AC2's statement now names `activeAt`, the map rule, a kept id, the map move, the warning and `closed`.
  - AC4's statement now names `load` keeping the range and the selected card and replacing Stats, the served PR and checks, and the no-history note.
  - The `check.sh` labels are unchanged; they summarise and stay true.
- F3: fixed: c0121's F9 bullet now carries the three missing details word for word (the node harness with `fetch` stubbed, a final case that stops the server, and the review check that no stub spawns a real process outside `.cache`). It landed on main as e0830282 through a capture worktree with `./zn land` (full gate passed), and the capture spend is recorded.
