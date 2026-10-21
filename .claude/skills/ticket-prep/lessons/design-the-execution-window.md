---
title: Design the window in which a raft runs against the old layout on origin
when: design
tags: [migration, shared-state, merges]
check: Between the commit that moves shared state (a counter, a map, a registry) and the merge, which copy does the branch's own tooling read and write on origin, and what does each merge of main do to the two copies?
---
A raft that moves shared state runs its own new tooling for its whole execution against an origin that still has the old layout. If the tooling chooses the file from the working tree, it reads and writes a copy origin doesn't have: its reservations reach nobody, and every merge of main conflicts on the old file, where the natural resolution silently drops main's updates.

**Why:** R0043 design review 002 F1: after c0114 moved the id counter into `z-nile/`, its branch's engine looked for the new file on origin/main, which had only the old one. An emergent issue would have reserved nothing, so its number could be handed out again on main, and every sync would have conflicted on the old counter file.

**How to apply:** let the tooling choose the live copy from origin's layout, never the working tree's. Make the merge of main resolve the two copies itself (keep the new layout's file at the higher value), and add a check that fails when a merge left them inconsistent. Write a spec for an origin from before the change and a branch after it.
