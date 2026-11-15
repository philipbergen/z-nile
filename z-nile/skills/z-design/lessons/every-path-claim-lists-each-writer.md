---
title: A design that guards every path to main lists every command that writes main, and the guard each passes
when: design
tags: [merge, gate, main, guards, enumeration]
check: Which commands write `main` (by a named search of the engine, such as `git grep -n 'refs/heads/main' z-nile/engine`), and which guard does each one pass?
---
A claim that a guard covers "every merge path" is only as good as the list of paths. A server rule with a bypass, a local gate or a shape rule each holds some writers and not others, and a writer left off the list is a hole the design calls closed.

**Why:** c0359's first design said the required `static` check, with an admin bypass for the tracker's own pushes, left only `gh pr merge --admin` open. Its review found that `./zn done` lands every raft on `main` by an admin push that skips the check, as do `./zn land` and the watch net's repair, and the sentence the design would have written into zz-rules ("a merge never does") was false on the day it landed.

**How to apply:** run the search, write a table of every writer (the dispatcher's gate merge, `gh pr merge` and the button, `./zn done`, `./zn land`, the broker and `publish`, the watch net), give each the guard that holds it and the spec that pins that guard, and word every restated rule from the table.
