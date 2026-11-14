---
title: A refusal that reads origin belongs inside the publish build
when: build
tags: [publish, refusals, origin]
check: Does a new refusal that reads `origin/main` (an item's status, a file) run inside the publish build, where the fetched base is already read, rather than as a separate read before it?
---
A separate read of `origin/main` before a publish adds a fetch and a window, and it breaks commands that run where the registry or origin is not set up yet. The publish build already reads the base it will commit on.

**Why:** c0250's prototype: a pre-read of the item's status for "only `./zn resolve` unblocks" broke `c0114/window.spec`, which runs `status` before the registry exists; moving the test into `setStatus`'s publish build fixed it.

**How to apply:** put the refusal in the function that builds the published change, on the base it read.
