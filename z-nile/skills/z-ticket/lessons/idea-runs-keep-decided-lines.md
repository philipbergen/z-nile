---
title: An idea run keeps the Decided lines
when: both
tags: [capture, process, decisions]
check: When `./zn idea` rewrites an issue that already had a Problem (a carried or filed-from ticket), does the new Problem still hold every `Decided with the user` and `Scope decision` line and the carried-from note of the captured text (`./zn capture <id>`), and if not, are they restored word for word before design starts?
---
`./zn idea <id>` with no `--text` drafts from the whole document and writes a new Problem as outcome bullets. On a ticket whose Problem already held the user's decisions, the draft turned them into Solution bullets and dropped the lines themselves, with their dates and quotes, and the note saying where the ticket came from. The decisions still read true in the Solution, but nothing on the document says the user made them.

**Why:** c0306's prep (2026-11-13): c0306 was filed from the retired c0261 with four `Decided with the user` lines (2026-11-08 and 2026-11-12) in one Problem paragraph. `./zn idea c0306` (verdict revise, F1 revised) left a three-bullet Problem without them.

**How to apply:** after `./zn idea` on a ticket with an existing Problem, diff the Problem against `./zn capture <id>`. The capture may not retype the sections (z-ticket step 4), so the prep restores each lost line word for word at the end of the Problem, saying where it came from.
