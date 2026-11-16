---
title: A new front-matter line sits beside lines nothing rewrites
when: design
tags: [tracker, front-matter, merge]
check: Where does the new front-matter line go, and does any command or step rewrite either neighbouring line (land rewrites `title:`, rafting `raft:`, prep `design:` and `status:`), which turns two independent edits into a merge conflict?
---
Git merges two edits on adjacent lines as one conflict. A front-matter line that a migration or a prep inserts beside a line another flow rewrites (a capture's `./zn land` retitling, a rafting PR's `raft:`, a prep's `status:`) conflicts with that flow whenever both are in flight, although neither touched the other's line.

**Why:** c0286 design review 001 F7: the design put `tied:` after `title:` and said "between two lines nothing else rewrites", but `./zn land` rewrites a capture's `title`. The line moved to right after `id:`, which changes only in an id rewrite that rewrites the new line's ids too.

**How to apply:** list who writes each neighbouring line (zz-rules: land, rafting, prep, the publisher) and place the new line beside ones nobody else edits; if none is free, state the conflict and how to resolve it.
