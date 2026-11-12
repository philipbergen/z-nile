---
title: Work done on every poll of a long-lived server is counted against the CPU limit
when: both
tags: [servers, cpu, caches]
check: What does one request of the long-lived process cost in CPU (measure it), how many requests does the process serve before its limit (`./zn` stops an engine at 1800 s of CPU), and is anything that only changes on a rebuild recomputed per request?
---
A server that re-encodes a multi-megabyte model on every 5-second poll spends 0.235 s of CPU per poll, so one open tab reaches the 1800 s limit in about 8 to 9 hours and the kernel kills the server.

**Why:** R0084 (c0121) code review 001 F2: the served board's `/api/state` encoded the 6.7 MB model per poll.

**How to apply:** encode (or render) once per generation of the data and splice the small per-request part in; add a spec that counts the expensive call over several polls (the module table lets a spec wrap it).

**Note (c0121 design review 011 F2):** take the cache generation in the same step, with no yield, as the data it labels. A generation read after a call that yields (`process.exec`) can label old data with a newer number, and the cache then serves it until the next change. Ask: is anything between reading the data and reading its generation able to yield, and is there a spec whose stub yields there?
