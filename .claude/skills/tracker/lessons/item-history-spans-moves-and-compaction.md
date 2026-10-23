---
title: An item's history spans its folders and its old ids
when: both
tags: [history, git, compaction]
check: Does every lookup of an item's past (its capture, its first review, its dates) read all of its folders (backlog, active/, done/), never infer identity across an id change (a compaction or a renumber) but mark it instead, and avoid `git log --follow`, which can latch onto a look-alike file?
---
Tracker items move between folders (`ready`, `stop`, `done`), were renamed by the layout migration (slug-named documents), and get new ids when `compact` or `renumber` runs. A `git log -- <current path>` misses every commit before the latest move or rename. `--follow` works only for one path, ignores `--grep`, and, since tracker files share templates, can take another item's similar file as the copy source.

**Why:** R0042 design reviews 007 F1 and F2, 008 F1, 009 F1, 010 F1 and 011 F1: seven rounds of id-change holes (007 to 013), each in a rule that inferred identity across an id change. The user chose a rule that never follows an id change and marks the result, and that one is always safe. The capture lookup in c0119's draft found nothing for items made before the 2026-10-05 compaction. That is half of the one-time audit list, so the scope check passed with nothing to check. The metrics reader's `--follow` dated a re-added review by another raft's identical file.

**How to apply:** use `z-nile/engine/trail.luau` (`trail.read`). It reads the item's three folders under its current id with `--no-renames`, and stops at the newest commit that changed `z-nile/compaction.txt` together with the item's document. Never walk back to an old id: mark the result instead. `capture` prints `(history before <sha> not followed: …)`, and a `Scope decision` settles it once. The same goes for anything the history can't settle (a renumber, two copies of one id). Where a date must survive id changes, use a field no id change rewrites, as metrics does with `created:`. Seed a fixture with a move, a legacy name, a compaction with a reused number, and a look-alike file.
