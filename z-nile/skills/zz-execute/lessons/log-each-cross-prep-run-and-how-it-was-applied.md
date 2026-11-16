---
title: The Verification log names each cross-prep run the Design asks for, and how it was applied
when: build
tags: [verification-log, handshake]
check: Does the Verification log name each cross-prep run the Design's Existing work asks for (a spec run with another prep's patch applied), with how the patch was applied, or what was done when it no longer applies to today's main?
---
A design that says "run X with another prep's prototype patch applied" is read later by the other raft to know the handshake was checked.

**Why:** R0086 review 001 F1: c0239's Existing work asked for docs.spec with and without c0194's `prototype.patch`; the patch no longer applied to `main`, and the log had no entry for it (nor for E2 or E6).

**How to apply:** for each such run, log it. When the patch does not apply, say so and record the hand merge of the shared lines (or a pin-by-pin reading of both specs) and the spec runs on the merged text.
