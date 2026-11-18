---
title: A subject the Problem says must not go unseen names the spec that selects it
when: design
tags: [affected, selection, watch, guards]
check: For each source the Problem says a change to must not go unseen (a hook, a shared module, a guard), does `lune run z-nile/affected -- <that source>` on the prototype list a spec that pins it, given the watch `./zn finish` will write from the layer's own sources, and if not, does the Design add a tooling spec with its own `<name>.watch.txt` naming it?
---
A ticket watch is the layer's own changed sources. A spec that pins a file the layer does not change (it drives a hook through real git, or reads a module another file requires) is never selected by a change to that file, so a tooling pull request that breaks it merges on a green `--affected` gate and is first seen by the full gate or the watch net.

**Why:** R0068 review-001 F1 (c0122): the Problem's point was that a change to the ref guard "would go unseen"; the new end-to-end specs pinned the hook, but their watch named only `fence.sh` (the one source the layer edited), and the selector listed neither them nor c0131's hook specs for the hook.

**How to apply:** in prep, run the selector on each subject with the specs in their promoted layout and the watch `./zn finish` will write. Where it misses, add a tooling spec outside `acceptance/` with its own watch naming the subject (d0297's form), and say in the Design which gate runs the full set.
