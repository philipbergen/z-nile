---
title: Every folder a case asserts on is made fresh in this run
when: both
tags: [specs, fixtures, caches]
check: Is each folder or cache a case asserts on created in this run (a new temporary folder), so no assertion reads state an earlier run left?
from: f0427 review F3 (2026-11-21)
---
A case that reads a warm cache passes whether or not the code does the work.

**Why:** f0427 review F3 (2026-11-21): "extracted once" was tested on a warm cache, so it proved nothing about the first extraction.

**How to apply:** point the case at a new folder under `.cache/`, run the command, and assert on what appeared. A mutant that skips the work must fail it.
