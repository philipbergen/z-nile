---
title: A daemon validates every path a client names, on its own side
when: both
tags: [security, daemon, paths]
check: When a daemon or helper reads a path a client names, does the daemon itself validate it both when the path is set and on every read, with a case that writes the raw message to the socket instead of going through the client?
from: f0437 review 001 F1 (2026-11-21)
---
A check in the client is not a check: anything that can write to the socket skips it. The daemon owns the rule, and it applies it when the path is set and again each time the path is read, because the file can change in between.

**Why:** f0437 review 001 F1 (2026-11-21): the live daemon served `/etc/hosts` over HTTP after a raw socket write named it, because only the client refused such paths.

**How to apply:** put the validation in the daemon's own function, call it at set time and at every read, and write a case that sends the raw message and expects the refusal. Add a mutant that removes the daemon-side check.
