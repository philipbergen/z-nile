---
title: A landed raft still owes zz-execute Phase 6 before the worker acts on the end line
when: build
tags: [landing, work, delivery]
from: c0385 and d0379 (lesson tickets, withdrawn 2026-11-16)
check: Before acting on an end line after a landing, has zz-execute Phase 6 run for that raft?
---
zz-execute Phase 6 is part of landing the raft: the watch-kick, the merge gate and cicd for a game change, `./zn spend <R> --phase deliver`, the final report on the pull request, and the cleanup. It must have run before the worker acts on an end line that follows a landing, whichever way z-work step 6 then directs (stop when a raft was named, take the next raft when none was).

**Why:** on 2026-11-15, with R0101, a worker read `end - <R> landed. Stop. …` from `./zn work next <R>` as "stop now" and left Phase 6 undone. Neither the line (`work.forRaft` in `z-nile/engine/work.luau`) nor either branch of z-work step 6 mentions Phase 6, so both read as "stop at once".

**How to apply:** when `./zn work next` answers `end` after a landing, run Phase 6 for that raft first, then say so and stop (raft named) or run `./zn work next` with no raft (none named). This lesson does not say what the end line means for taking another raft. **Note (d0379):** the same incident was captured as a defect to reword that line and z-work step 6; it was withdrawn with c0385 (user, 2026-11-16), so the wording is unchanged and this lesson is the guard.
