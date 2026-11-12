---
title: A session-scoped helper is stopped by the SessionEnd hook too, because `/clear` ends a session and keeps its process
when: design
tags: [session, reaper, hooks, background]
check: For each helper tied to "the session", what stops it on each SessionEnd reason (clear, exit, logout), and does a case over a process table show the session-end reaper stopping it?
---
A pid-liveness check on the session's process never fires on `/clear`: the `claude` process lives on while its conversation (and its background commands) end.

**Why:** c0275 design review 001 F2: the background beater was tied to the `claude` pid only; this repository's own rule ("a `/clear` ends the background commands of the conversation it clears") was not met, and the claim would have read live for about an hour afterwards.

**How to apply:** give the helper's command line the session pid and let the session-end reaper stop it by that, with a table case; keep the pid check as the second line.
