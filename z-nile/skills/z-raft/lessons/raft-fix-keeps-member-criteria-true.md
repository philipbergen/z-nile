---
title: A raft-level fix for a prototype failure keeps every member's criterion true at real scale
when: design
tags: [raft, prototype, criteria, scale]
check: Does the fix make any member's acceptance criterion or Design sentence false on the real tree while its spec still passes on small fixtures, and did the cause come from probes that separate the variables?
---
A fix that changes how many processes, files or passes a member promises ("one `git cat-file --batch` for any number of items") turns the promise false on the real tree while the member's spec, which builds a small fixture, still passes. The executor then edits the member's criterion, which changes its approval contract.

**Why:** R0099 design review 001 F2: the first answer to a hang in the board build was a chunked read (one `git cat-file --batch` per 400 keys), which made c0284's AC3 false at scale; the stated cause (output size) was also wrong, because one probe changed stdin and output together. Streaming one process kept both members' text true.

**How to apply:** probe one variable at a time, record each result, and prefer the fix that leaves every member's wording true; when none exists, the member goes back to z-design (`./zn unfold`), never a raft-level rewording.
