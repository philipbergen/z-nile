---
title: A spec that replaces PATH keeps the guard stubs first
when: both
tags: [specs, guards, path]
check: Where a spec replaces PATH, are the runner's guard stubs (the recording open and xdg-open) still first on it, and does every command that could open a browser get the no-open flag?
from: f0427 review F2 (2026-11-21)
---
A bare `PATH=/usr/bin:/bin` hides the stubs, so the real `open` runs.

**Why:** f0427 review F2 (2026-11-21): `embed.spec` ran `zn board` with `PATH=/usr/bin:/bin` and the real `open` ran on the owner's machine.

**How to apply:** build the new PATH as the stub folder followed by the folders you need, pass the no-open flag, and assert the recording stub saw no call.
