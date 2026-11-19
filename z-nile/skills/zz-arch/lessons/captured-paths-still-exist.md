---
title: A writer fed by a diff's file list keeps only the paths that still exist
when: build
tags: [git, diff, deletions, watch]
check: When code records paths from `git diff --name-only` (a watch list, a sidecar per changed file), does it drop the paths the change deleted, with a case where a layer deletes a spec and a source?
---
`git diff --name-only <base> HEAD` lists deleted paths too. A writer that treats every listed path as a changed, living file writes records about files that are gone.

**Why:** d0410 (R0125, 2026-11-17): `./zn finish`'s watch capture wrote a `<stem>.watch.txt` beside each spec c0202 deleted (making `tests/unit/Pay/` again, which c0202's place.spec forbids) and listed the three deleted sources in `acceptance/watch.txt`, which `watch-check` refuses. Every layer that deletes a spec or a source could not finish; c0202 was the first such layer.

**How to apply:** filter the list by `fs.isFile` where the records are written (keep the plain diff for a caller that must see deletions, such as an affected selection), and spec a layer that deletes a spec and a source, plus one that deletes nothing.
