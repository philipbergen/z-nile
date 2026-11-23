---
title: A check of a folder binds nothing above it
when: both
tags: [paths, cache, symlink, trust]
check: When code verifies a folder before trusting what is in it (owner, mode, contents, a digest), does it also verify every ancestor up to a root nobody else can write, so the folder cannot be swapped by renaming or relinking a parent?
---
A verified folder is only as fixed as the path that leads to it. Whoever can write a parent can replace the checked folder between the check and the use.

**Why:** f0427 step 2 (2026-11-21, code review): the Go app checked its extracted cache folder on every run, but not the folders above it; a writable parent let the whole cache be replaced after the check. The fix walks the ancestor chain and refuses a parent another user can write.

**How to apply:** for any trusted directory, check the chain, open by the checked handle where the platform allows, and write a test that swaps a parent.
