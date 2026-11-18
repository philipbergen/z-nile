---
title: A promised failure names only what the assertion prints
when: design
tags: [raft, risks, specs]
check: Where the raft document says a failure "names" an item, does the assertion behind it print ids, or only a count?
---
A Risks line that says a red case will name the folder at fault is a promise about the spec's message. A case that compares two counts reports "expected 122, got 121" and no id, so the reader of that failure has nothing to go on.

**Why:** R0135's Risks said a leftover folder turns c0042's cli case red "naming the folder". The raft half of that case compares counts; only the issue half lists ids (review-001 F1, 2026-11-18).

**How to apply:** Before writing what a failure reports, read each half of the assertion. Say "a count off by one" where that is all it prints.
