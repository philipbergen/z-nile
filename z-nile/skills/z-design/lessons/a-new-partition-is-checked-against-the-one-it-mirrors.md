---
title: A new partition is checked against the existing one it must agree with, over the real tree
when: design
tags: [selector, partitions, real-tree]
check: When the design adds a classification (a suite, an owner, a tier) that decides what runs, and an existing mechanism already classifies the same things by another rule, does a case on the real tree take every member of the existing classification and assert the new one gives the same answer, rather than pinning the new rule on hand-picked paths?
---
Two rules that sort the same items drift apart wherever one is written by location and the other by what a table forces. Cases on chosen examples pin the new rule as correct, including its disagreements.

**Why:** c0083 design review 001 F1: `suites.changed` sorted root files (`.models.toml`, `LICENSE`, `.github/`) under no suite, while the watch map already gives them to the tooling's specs, so `--suite changed` skipped 37 watched entries' specs that the bare gate ran. AC1's cases were hand-picked and pinned `AGENTS.md` as touching nothing.

**How to apply:** derive the new rule from the existing one's data, and add a real-tree case that walks every entry of the existing classification (here every path of every watch list) and checks the new answer contains that entry's own suite. A case that fails on the first prototype is the proof it can fail.
