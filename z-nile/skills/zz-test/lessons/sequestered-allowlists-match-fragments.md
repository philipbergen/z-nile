---
title: A sequestered allow-list matches fragments, not whole lines of code that does not exist yet
when: design
tags: [sequestered, allowlist, scans]
check: Does a scan in a sequestered spec allow lines by their whole text, and will the executor's wording of those lines be the one the spec names?
---
A sequestered spec cannot be edited during execution. An allow-list keyed on the exact text of a code line breaks the day the executor words that line differently, and nothing can be done in the raft.

**Why:** c0194's `callers.spec` first listed the exact `mktemp -d` and `/tmp` lines of `tmp.luau`. A reword of one line failed the scan with nothing to edit. It now allows by a fragment per file (`"mktemp", "-d"`, `.sentinel.XXXXXX`) with the reason beside it.

**How to apply:** key allowances on a short fragment per file plus its reason; keep exact-line lists (like `cachepaths.ALLOWED`) in non-sequestered harness files the executor edits and a reviewer checks.
