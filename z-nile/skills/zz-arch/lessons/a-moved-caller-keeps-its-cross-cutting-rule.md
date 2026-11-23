---
title: A caller moved to another file keeps every rule its old place carried
when: build
tags: [refactor, gate-queue, exit-codes]
check: When code moves out of a file, has every rule that file's other callers follow (a not-started exit, a refusal, a cleanup) been carried to the new place, and does the spec that counts those callers count the new file too?
from: full gate of d0434-restack, 2026-11-22 (#756)
---
A rule applied at each caller, rather than in the thing called, is lost silently when one caller moves.

**Why:** d0434 moved restack out of main.luau while d0426 had just given every check caller the rule 'exit 75 means the gate did not start, not that the check failed'. The moved code lost it: a restack run while another gate held the machine would have marked a healthy layer red. Only a spec that counts the callers caught it, at the lead's gate.

**How to apply:** before moving a block, list what its neighbours do around the same call; after, grep the old file's callers and compare. Prefer the rule inside the helper.
