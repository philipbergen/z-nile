---
title: A sequestered file is judged per item, never per blob
when: design
tags: [security, guards, git]
check: Can a deletion pair with an unrelated addition elsewhere in the change (a decoy), can a new file stand in for an existing one (another folder of the same item, another case on a case-insensitive disk), and does a legitimate move that rewrites the content (a check.sh whose paths follow its item) still pass?
---
"A move is the same blob deleted here and added there" is not what a move is: a step paired the item's `check.sh` with a decoy copy in another item's folder and added a weak one where the item went; a `CHECK.SH` beside `check.sh` is an addition to git and an overwrite on macOS; and `ready` rewrites a moved `check.sh`'s own paths, so a real move isn't a pure one. Judge each item the change touches: the set of its sequestered files (relative to its folder) is the same before and after, each unchanged or exactly what the move's own rewrite produces; it lies in one folder after; only a new item adds them; a sequestered name in another case, or any added path that differs only in case from another, is refused.

**Why:** c0117 design reviews 002 F2 and 003 F1: the same rule failed twice through two mechanisms.

**How to apply:** compute the per-item maps from both trees (`ls-tree -r`), not from the diff alone; spec the decoy, a spec moved to another item, `CHECK.SH`, and a `ready` whose `check.sh` names its own path.
