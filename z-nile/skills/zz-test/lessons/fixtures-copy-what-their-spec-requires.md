---
title: A fixture that copies a real spec also copies what the spec requires
when: both
tags: [fixtures, sequestration, checks]
check: For each real file a check.sh or spec copies into a fixture home, which of its requires resolve through the fixture's own `.luaurc` (an `@tests/...` module, a sibling helper), and is each of those copied too, or the file loaded through a one-line re-export?
---
A copied spec loads only what the fixture holds. When a later change on `main` adds a require to the real file, every sequestered check that copied it breaks, and a sequestered `check.sh` can't be edited without the user.

**Why:** R0076 (c0185) code review 001, candidate lesson. AC6's fixture copied pickman's `architecture.spec.luau` alone. R0065 then made that spec require `@tests/meta/tiers`, so the copy died with `could not resolve child component "tiers"`, and the user had to approve a one-line edit of `check.sh` during execution.

**How to apply:** at prep, list the copied file's requires and copy each into the fixture (or load the real spec through a re-export), and add a case that fails when a require is missing. Rerun the check against current `origin/main` just before the raft is readied.
