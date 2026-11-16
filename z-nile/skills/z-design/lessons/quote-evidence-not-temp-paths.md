---
title: A Problem's evidence quotes its logs; a session's temporary paths don't last
when: both
tags: [docs, records, review]
check: Does every log, output or file the issue cites as evidence live in the repository or in the issue's own text (the relevant lines quoted, with their times), rather than only as a path into a session's scratchpad, `tasks/` or `/tmp`?
---
An agent session's scratchpad and background-task outputs (`/private/tmp/claude-…/scratchpad/…`, `…/tasks/<id>.output`) are deleted when the session ends. An issue that cites them as its evidence loses it: the next reader (a reviewer, the follow-up that must read the next occurrence) finds a dead path.

**Why:** c0132's Problem cited each sweeper kill by a scratchpad path. Design review 004 F1 dated the kills from those files' times (each within the first minute or two of z-nile's suite), which the document didn't record, and noted that the paths would vanish with the session.

**How to apply:** quote the lines that matter (the failing stage, the error, the counts) and the times that date them into the issue's text, or into the follow-up that will need them. A path to a temporary file may stand beside the quote, never instead of it.
