---
title: process.exec with a stdin over about 128 KB deadlocks against a filtering child
when: design
tags: [lune, process, stdin, git]
check: Does any `process.exec` pass a stdin whose size grows with the repository (one key per commit or document) to a child that writes as it reads?
---
`process.exec` writes all of stdin before it reads stdout. A child such as `git cat-file --batch` fills its output pipe, stops reading, and both sides wait for ever, at 0 % CPU.

**Why:** R0099 prototype: `who.fronts` sent every document revision's key (about 2,500 on this repository, 150 KB) in one `process.exec`; the board build never returned. Probes: 10,000 short keys stall, 8,000 do not; the output size is not the variable.

**How to apply:** use `process.create`, write the keys from a `task.spawn`, close stdin and read stdout to the end, or write to a file and redirect it. Probe with the size the real tree reaches, not a fixture's.
