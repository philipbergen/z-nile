---
title: A hand-written tokenizer advances on every branch or refuses
when: both
tags: [parsers, loops, hangs]
check: Does every loop over the input advance on every branch, and which input makes a helper return its own start index (a character it stops at but never consumes)?
---
A word reader that stops at a character the caller does not handle makes the caller call it again at the same index, forever. A well-meant input (a `\.` in a grep pattern) then hangs an unattended step while it holds a lock.

**Why:** R0052 code review 004 F3: `raftcheck.word` ended a bare word at `\` without consuming it; the caller's loop saw `\` that was not a line continuation and looped on the same index, so the dispatcher hung at the rafting gate. No case had a backslash outside a continuation.

**How to apply:** give a tokenizer a case for every character class it treats specially at every position (bare, quoted, after a word), refuse what it does not understand (fail closed), and add a progress guard to the loop (`if next <= at then refuse`), so a later slip refuses instead of looping.

See also c0193, which plans the general rule (`zz-arch/scanning-loops-advance`); its executor merges the two into one lesson.
