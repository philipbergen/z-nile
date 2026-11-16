---
title: A review's round number is comparable only within its own folder
when: design
tags: [reviews, rounds, folders]
check: Does any rule order review files from several folders (a raft's and its members', or several members') by their `NNN`, when each folder numbers its own rounds from 001?
---
Round numbers are per folder: a raft's folder and each member's folder (c0248's per-layer reviews) each number their reviews from 001. Comparing `review-002.md` in one member with `review-001.md` in another says nothing about which came later. A rule that takes "the newest round" across folders by number then picks an arbitrary one.

**Why:** c0251 design review 001 F11 (2026-11-15). Choosing the previous round's reviewer compared round numbers across member folders, which c0248 numbers independently.

**How to apply:** take the newest round per folder by its number, then combine folders by a rule that does not use the number. Lifecycle rank works: at the top rank, every folder's newest counts. So does an order the files record themselves.
