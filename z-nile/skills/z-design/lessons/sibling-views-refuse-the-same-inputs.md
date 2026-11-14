---
title: Two views of one reader answer, refuse and truncate the same inputs
when: design
tags: [views, readers, refusals]
check: For each input the command refuses or reads differently (a bad file, a shallow clone, an item with no published history), what does the second view (board, page, JSON) do with it, and is there a case that runs both on that input?
---
"The same entries" is about every input, not the happy one. A command that refuses a bad `spend.md` while the page prints the item without its worker, or one that reads a shallow clone's truncated log while the page falls back to stored rows, shows the reader two answers.

**Why:** c0284 design review 001 F7: the board's guard on `history.read` (non-shallow only) and its tolerant spend reader both differed from `./zn who`.

**How to apply:** list the refusals and fallbacks of the command and give the view the same one for each (or write the exception down and ask); a case for each runs both and compares.
