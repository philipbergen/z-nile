---
title: A rule over paths does not bind what the file is
when: both
tags: [security, paths, links]
check: For a file served or read after a path check (name, folder, root, symlinks), does the code refuse hard links (link count other than 1) and compare what was checked with what was opened, by the same file on the opened handle?
from: f0437 review 002 N-F1 (2026-11-21)
---
Names, folders, roots and symlink checks all describe a path. Two paths can name one file, and a path can change between the check and the open.

**Why:** f0437 review 002 N-F1 (2026-11-21): a hard link named `index.html` to a private file passed every path rule and was served.

**How to apply:** refuse a file whose link count is not 1, open it, then compare the opened handle's identity (device and inode) with the one checked. Give each a case: a hard link, and a file swapped between check and open.
