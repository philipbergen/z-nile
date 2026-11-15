---
title: A shape the real-tree audit judges is checked on every path that pushes it to main
when: design
tags: [audit, land, gate, direct-push]
check: Which paths push a file the real-tree audit judges to main without the full gate (`./zn land`, `publish`), and does each run the same checker, so one malformed push cannot turn every later gate red?
---
The real-tree audit spec runs in every full gate. A new shape it judges, written by a path that lands directly after only the static stages, lets one bad push stop everyone's gate until a repair lands.

**Why:** c0260 design review 009 F5: `./zn land` checked only the Ask rule, so a capture with a gap in its Interview numbering would have landed and turned `c0082/real-tree` red for every raft.

**How to apply:** run the shared checker in the direct-push path for the documents it changes (marked ones only, when older documents have a shape of their own), and add land cases that refuse a malformed record naming the problem and land a valid growing one.
