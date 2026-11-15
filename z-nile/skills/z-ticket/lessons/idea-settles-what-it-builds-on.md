---
title: An idea says which prepared item it builds on, before design starts
when: design
tags: [capture, overlap, scope]
check: Does the idea name every prepared or in-flight item that already designs part of what it asks for, and say for each whether this issue builds on it, waits for it or replaces it?
---
z-ticket's duplicates step looks for the same issue twice. It also has to look for a prepared issue that already designs a part: the idea then says whether it builds on that item (and depends on it), or the capture is split so each part has one home. Left to design, the overlap comes back as a question to the user, or as a second format for the same thing.

**Why:** c0316 (Goals and escapes), 2026-11-13: the capture listed c0250 under "for the design to order against" and still asked for a new committed question file. c0250, prepared, already designs that file (`escalation.md`). Design had to stop and ask the user, who split the issue in two (c0321). The idea stage could have settled it: c0250 was on `main` when the idea was written.

**How to apply:** at capture, search the backlog for the nouns the idea introduces (a file, a command, a status). For each prepared or in-flight item that owns one, write the relation into the idea's text before `./zn idea` runs, and put the id in `depends_on` when the issue builds on it.
