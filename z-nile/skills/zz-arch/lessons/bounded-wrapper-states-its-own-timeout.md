---
title: A bounded wrapper states its own timeout and does not call every quiet failure one
when: both
tags: [process, errors]
check: When the wrapper's child fails with no stderr, does the caller learn what happened (timeout, missing command, killed), or is every empty failure reported as a timeout?
---
A wrapper that bounds a child by a limit must say when the limit fired itself (a marker it writes, or a distinct exit code); a missing command exits 127 silently and reads as a timeout if the caller guesses from the empty stderr.

**Why:** R0100 review-001 F3 (`netRun` reported every empty-stderr failure as a timeout).

**How to apply:** have the wrapper print or exit with its own timeout marker, report a missing command as such, and add a spec case with a command that does not exist.
