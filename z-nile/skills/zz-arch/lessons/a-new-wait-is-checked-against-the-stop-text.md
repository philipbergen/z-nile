---
title: A new wait answer is checked against what the skill reads
when: both
tags: [worker, wait, skill, text]
check: When work next gains a new wait or stop answer, has its exact text been checked against the prefixes and words the z-work skill and the dispatcher match on, with a spec that pins both sides?
---
The worker loop is driven by text. A new answer that does not match what the skill looks for is read as something else, usually as 'nothing to do'.

**Why:** f0420 step 4b (2026-11-21): the new 'held by another worker' answer did not start with the Stops prefix the skill matches, so a worker would have ended instead of waiting.

**How to apply:** one constant for the prefix, used by the engine and quoted by a spec that reads the skill file.
