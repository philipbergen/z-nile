---
title: A pin's refusal names the entry that differs, never the pin
when: design
tags: [guards, pins, usability]
check: Can an ignored file the user's tools create (`.DS_Store`, an editor backup `*~`) make this guard refuse, and does the refusal name the entry that differs (unexpected, missing, changed) without printing the value that would make it pass?
---
A content pin over a working folder also pins the ignored files in it. A guard that fails closed on a mismatch with only "refusing" leaves agents told to stop with no clue, or tempted to re-pin to get past it.

**Why:** c0123 design review 001 F3: the fence pins the SHA-256 of `z-nile/lib/git-hooks/`; an empty `.DS_Store` (ignored by `.gitignore`, so invisible to `git status`) made every fence, `check.sh` and gate refuse with `no ref guard … Stop and report this`. Review 002 F4: the first diagnosis split names on spaces and expanded `*`, so a Finder duplicate `pre-push copy` was reported as `unexpected copy`.

**How to apply:** keep the strict pin, add a names list beside it, and say what differs in whole names (walk the folder by glob, never `ls` through word splitting): `unexpected <name>`, `missing <name>`, else "a file differs in bytes or kind". Never print the pin value in a message. Add cases for an extra file, a missing file, a name with a space and a name that is a glob, each checking the message names it and does not contain the pin.
