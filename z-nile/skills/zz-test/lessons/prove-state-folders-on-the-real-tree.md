---
title: A new state folder is proved by the full gate on a copy of the real tree that holds one
when: design
tags: [state, folders, regression]
check: After this rule's first real use on today's tree (the new folder holding a real item), does the full gate still pass on a copy?
---
A new place where items can live (a state folder, a retired area) is invisible to every reader that walks the old places, and promoted specs and test helpers are readers too. Checking the readers you changed proves nothing about the ones you didn't know about.

**Why:** c0116 design review 002 F2: E2 showed that `lessons` and `metrics` read `rafts/retired/`. But the first real retirement (R0040, on a copy of today's tree) turned three promoted specs red (c0114/classified, c0043/rounds, and c0005/worktree through `engine.empty`), which none of the design's lists named.

**How to apply:** in prep, put a real item in the new folder on a copy of today's tree (the way the command does it, with a non-fixture identity so the tripwire accepts the copy) and run the full gate there. Every red spec goes on `Overrides:`, every helper that walks the folders gains the new one, and a sequestered case keeps one such copy green.
