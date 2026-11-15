---
title: The affected selector is run with file paths, not directories
when: design
tags: [affected-specs, selector, touched-modules]
check: Was every path given to `lune run z-nile/affected` a file (a feature's `init.luau`, never its directory), and does the Affected specs count match a rerun with the Touched files spelled out?
---
`lune run z-nile/affected -- pickman/src/shared/Logic/View` prints nothing and exits 0, and so does any directory (`pickman/src/client`, a feature folder). The design template's "file or directory prefix" lets a prep list a directory and believe its specs were selected. A list that mixes files and a directory looks complete and quietly drops every spec that only the directory's files select.

**Why:** f0235 design review 001 F5. The Affected specs list ran the selector with `pickman/src/shared/Logic/View` and missed 20 specs, `f0126/views` and `f0109/place` among them, both named in the Regression guard. The suite run (E3) still covered them, so no override was missed, by luck.

**How to apply:** give the selector each file the Touched modules name (`.../View/init.luau`), and compare the count with the list. Until the selector expands or refuses a directory (a z-nile defect to capture), never pass one.
