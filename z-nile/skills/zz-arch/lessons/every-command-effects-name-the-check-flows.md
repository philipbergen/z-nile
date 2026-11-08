---
title: An effect added to every command names every process that runs those commands, and whether it fires there
when: design
tags: [commands, checks, fence]
check: Which check.sh files, gate steps and specs run this command in the real checkout, and what does the new effect (a fetch, a push, a write) do there?
---
A side effect added to "every `./zn` command" also runs inside nested calls from check.sh files and the gate, where the fence lets a fetch and a network push through.

**Why:** c0265 design review 003 F2: an automatic heartbeat would have pushed a ref to the real origin from nested `./zn lessons --check` calls, depending on the wall clock.

**How to apply:** decide from the fence's own facts (`PICKMAN_FENCE_REAL_GIT`) in one pure function, and pin a fixture case for the nested call.
