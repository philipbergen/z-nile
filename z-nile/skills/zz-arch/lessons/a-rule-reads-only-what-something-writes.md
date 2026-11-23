---
title: A rule reads only a field that something writes
when: both
tags: [facts, membership, tributary]
check: For each field a new rule reads, is there a command that writes it in every way the thing can come to exist, and a test that follows one item through each of those ways?
from: code review of f0420 (theme at a time), 2026-11-22 (#758)
---
A rule tested on hand-written fixtures passes while the real commands never produce the field it reads.

**Why:** a theme's membership was read from a raft's tributary line, which no command wrote; a worker on a theme would bundle a ticket and then be told the theme had nothing open.

**How to apply:** grep for writers of the field before trusting it; add a journey spec that creates the item through the real commands and asks the rule at each step.
