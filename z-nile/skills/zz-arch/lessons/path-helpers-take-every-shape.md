---
title: A helper that splits a path handles a path with no folder part
when: both
tags: [paths, helpers, fail-closed]
check: For a helper that derives a folder, an owner or a name from a file path by string arithmetic (`string.sub(path, 1, #path - #base - 1)`), what does it give for a bare file name at the repository root, a trailing `/` and an empty string, and is each one a fixed answer rather than a throw or the whole path?
---
Cutting the base name off a path by length assumes a `/` before it. For a file at the repository root there is none, so the cut returns the whole path. The folder lookup that follows then reads a file as a folder and throws.

**Why:** c0306 prep (2026-11-14). `reviewfiles.markedFolder` found a review's owner document by cutting the base name off the path. The slow tier's `c0117/ledger` commits a `review-001.md` at the repository root, and `./zn commit` threw "Not a directory" until the helper treated a path with no folder part as unmarked.

**How to apply:** give a path helper a guard for each shape (`#path > #base`, a `/` present) that returns the fail-closed answer the caller expects, and add a case for a root-level file. Prefer a matcher that captures the folder (`string.match(path, "^(.*)/[^/]+$")`), which gives nil for a bare name.
