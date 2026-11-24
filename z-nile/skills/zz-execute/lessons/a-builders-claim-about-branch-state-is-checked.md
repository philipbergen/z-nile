---
title: A builder's statement about a branch is checked before it is repeated
when: build
tags: [builder, reports, merge]
check: Before telling the owner what a builder said about a branch (what it contains, what is merged, what passes), has the lead checked it with one command?
from: report of the c0435 builder, 2026-11-22
---
A builder reports what it believes at the end of a long run; its picture of main can be hours old.

**Why:** a builder reported that main's recent merges were not in its branch and that main had no per-activity model tables. Both were false: the branch was level with main, which had the tables. A weaker test had been written on the false belief.

**How to apply:** rev-list against origin/main and a grep settle it; say what was checked when passing the report on.
