---
title: An item whose checks run another item's promoted specs lands after it, and never in its raft
when: design
tags: [order, rafting, promotion, check-paths]
check: Does this item's check.sh name another item's promoted specs (tests/acceptance/<other>/…)? Then is the prep landing after that item is done (check-paths is red on main until then), and is the item kept out of that item's raft (done runs every check.sh before promoting anything)?
---
A check.sh that runs another item's specs at their promoted path (`tests/acceptance/<other>/`) can only pass once that item is done. Until then c0120's promoted check-paths lists those paths as missing, so the prep turns z-nile's gate red the moment it targets main; and in one raft with that item, `./zn done` runs every check.sh before it promotes any spec, so the check load-fails and done always refuses. Two items whose sequestered specs contradict each other (one pins "planned", the other its absence) can't share a raft either.

**Why:** c0121 design review 003 F1: c0121's AC6 ran c0118's promoted specs, and c0118's G9 allowed z-raft to raft the two together; the prep failed check-paths, and the combined raft could never pass done. The user chose "Sequence, c0121 solo".

**How to apply:** sequence the preps (the dependent one lands after the other is done), mark the dependent one `solo: true` with the user's decision, say the expected reds until then in the design and the PR, and check the other item's design does not name this one as a raft partner.
