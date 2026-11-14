---
title: A refused shell call runs none of its steps
when: both
tags: [bounded-commands, hooks, git]
check: After the hook refused a shell call that chained several steps (a `git commit`, a push, a background job), did you check `git log` and the working tree before going on, since none of its steps ran?
---
The PreToolUse hook judges a whole call. When it refuses one step (a bare `&` job), the earlier steps in the same call never run either, a `git commit` among them, and nothing says so but the refusal.

**Why:** c0248's prototype re-run: a call that committed and then started a background job with `&` was refused, and the commit was silently missing until `git log` was read.

**How to apply:** keep commits and pushes in their own calls, start background work only through `./zn run --time`, and read `git log -1` after any refused call.
