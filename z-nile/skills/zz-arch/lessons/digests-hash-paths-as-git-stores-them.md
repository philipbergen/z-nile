---
title: A content digest hashes a path the way git stores it, never through a call that follows links
when: both
tags: [digest, symlinks, fail-closed]
check: Does the digest treat a link (to a file, a folder, or nothing) as a link with its text, so adding, retargeting or removing it moves the digest, and does any other kind of path turn reuse off instead of being dropped?
---
`fs.isFile` follows links: a link to a folder or a dangling link looked deleted, so changing it left a digest unchanged.

**Why:** R0081 code review 003 F2: removing the `.claude/skills` link of a new skill left the gate digest unchanged while `./zn skills --check` started failing, and `gate-check` still said "reused".

**How to apply:** test `-L` first, hash the link text as mode 120000, hash regular files by content, and treat a path that is neither as unreadable.

Also a submodule (mode 160000): git lists it as a folder whose files never arrive through `--others`, so it is not "now a folder, deleted". Any gitlink turns reuse off (R0081 review 005 F2).

A path's index state is part of how git stores it too (tracked or not, its staged mode): a spec or stage that reads the index is reused after an index-only change unless the digest marks it. Check: for each reader of `ls-files` in the gate, does changing only the index move the digest? (R0081 review 006 F1.)
