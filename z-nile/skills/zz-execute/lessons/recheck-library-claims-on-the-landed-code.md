---
title: Re-derive a design's claims about a library from the code that landed
when: build
tags: [verification, stubs, cross-raft]
check: For each library call my design expects to succeed after a sequence of other calls (a pass after a slow read, a cache hit after a write), does the landed library's code agree line by line, including every call in between that may reset the state, and does any spec drive that sequence through the real module rather than a stub?
---
A design written against another issue's design describes that library as it was planned. Its review fixes can change internal state (an allowance, an in-flight flag, a cache) without changing a signature, so every check stays green against stubs while the outcome the design promised no longer happens.

**Why:** R0117 code review 001 F1 (f0208): §5 reasoned that after `CHECK_SECONDS` of busy answers "that late read has already set Wallet's pass allowance". f0201's own code review (R0110 F2) made every busy answer clear that allowance, so a PLAY still busy at 10 s wrote no pass and the player was teleported to be sent back. The executor saw it, but its first check was the signatures; the sequestered server spec's stub `pass` always answers true, so 143 cases stayed green.

**How to apply:** at the start of a layer that wires a library which landed after the design, list every sentence of the Design that says what the library's state will be after a sequence, read the landed code for each call in that sequence (not just the signature), and run one probe of the sequence through the real module under `./zn run`. A claim that no longer holds is not a local deviation: put it under the raft's `## Open to the human` in the same commit that logs it, with options and costs.
