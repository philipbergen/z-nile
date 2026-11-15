---
title: Restack onto main immediately before the trace, not once at the start
when: build
tags: [restack, trace, done, main]
check: Is the stack on the current origin/main at the moment `./zn trace` and `./zn done` run, with every member check rerun on the restacked result?
---
`trace.md` names the stack's `Commit:` and line numbers; a restack after it makes the table stale, and layer 1 falls behind main whenever anything else lands during a long raft.

**Why:** R0100 final review F3. The raft ran for days; layer 1 was five commits behind main by the final review, so the table was stale before it was read and `./zn trace` refused.

**How to apply:** do the restack as the last step before `./zn trace`, with the pick helper if it stops at conflicts, push each rebuilt layer before the next `./zn finish`, rerun every member's `./zn check` and the affected gate on the result, then build `trace.md` and `./zn done` at once; if main moves again, restack and rebuild the table again.
