---
title: An item's history spans its folders and its old ids
when: both
tags: [history, git, compaction]
check: Does every lookup of an item's past (its capture, its first review, its dates) read all of its folders (backlog, active/, done/) and its id before the last compaction, without `git log --follow`, which can latch onto a look-alike file?
---
Tracker items move between folders (`ready`, `stop`, `done`), were renamed by the layout migration (slug-named documents), and get new ids when `compact` runs. A `git log -- <current path>` misses every commit before the latest move or rename. `--follow` works only for one path, ignores `--grep`, and, since tracker files share templates, can take another item's similar file as the copy source.

**Why:** R0042 design review 007 F1 and F2. The capture lookup in c0119's draft found nothing for items made before the 2026-10-05 compaction. That is half of the one-time audit list, so the scope check passed with nothing to check. The metrics reader's `--follow` dated a re-added review by another raft's identical file.

**How to apply:** use `scripts/tracker/trail.luau` (`trail.read`): the item's three folders, plus the renamed id before the cut in `tracker/compaction.txt`, with `--no-renames`. Seed a fixture with a move, a legacy name, a compaction with a reused number, and a look-alike file.
