---
title: A new gate names where the fix it demands can be committed
when: design
tags: [gate, trace, lifecycle, harvest]
check: For each refusal this design adds, when is the file it asks for written, and does every check that runs before the landing (the trace's late-file list, the capture scope, the approval contract) allow that file to change then?
---
A gate that refuses until a file exists is only as good as the path to writing that file. Later stages seal things: the trace allows a short list of files after `trace.md`, a capture may change only some keys, an approval hashes the contract. A design that adds a refusal walks the fix through each of those and names the one that has to learn the new file.

**Why:** c0316 (Goals and escapes), 2026-11-13: the design made `./zn done` refuse a raft with an unharvested final-review finding. The final review is written after `trace.md`, and `trace.luau` called any later commit that touched `harvest.md` or a lesson file stale, in two separate checks. The gate would have asked for an entry there was no legal way to commit. The subagent writing the gate spec found it while building the fixture; the design had only read the gate's own code.

**How to apply:** for every new refusal, write the fix as the user would do it (which file, which commit, at which point of the lifecycle) and run it past each seal between that point and the landing. Give the fix its own spec case, on the real CLI, that ends in the landing.

**Note (c0264 final review 001 F1, 2026-11-14):** the same shape on a gate that reads history: `./zn trace` refused a ticket whose capture commit (a `./zn new` stub on `main`) had no `## Solution`, and 26 of 46 designed tickets were in that state. Check: for a refusal that reads history, how many open tickets already fail it on the day it lands, and which commit lets each satisfy it? c0330 fixed the gate.
