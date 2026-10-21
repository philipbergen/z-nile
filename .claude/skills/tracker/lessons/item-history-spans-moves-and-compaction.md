---
title: An item's history spans its folders and its old ids
when: both
tags: [history, git, compaction]
check: Does every lookup of an item's past (its capture, its first review, its dates) read all of its folders (backlog, active/, done/) and its id before each compaction (each one writes only its own map) and each renumber (`tracker/renumbered.txt`), without `git log --follow`, which can latch onto a look-alike file?
---
Tracker items move between folders (`ready`, `stop`, `done`), were renamed by the layout migration (slug-named documents), and get new ids when `compact` or `renumber` runs. A `git log -- <current path>` misses every commit before the latest move or rename. `--follow` works only for one path, ignores `--grep`, and, since tracker files share templates, can take another item's similar file as the copy source.

**Why:** R0042 design reviews 007 F1 and F2, 008 F1 and 009 F1, three rounds of id-change holes. The capture lookup in c0119's draft found nothing for items made before the 2026-10-05 compaction. That is half of the one-time audit list, so the scope check passed with nothing to check. The metrics reader's `--follow` dated a re-added review by another raft's identical file.

**How to apply:** use `scripts/tracker/trail.luau` (`trail.read`): the item's three folders, plus, walking back through every commit that changed `tracker/compaction.txt`, the id each one renamed, with `--no-renames`. Match a capture subject against the id the item had at that commit. A tool that changes ids leaves a record the trail can read, and a fallback is marked so it is never mistaken for the real thing. Seed a fixture with a move, a legacy name, a compaction with a reused number, and a look-alike file.
