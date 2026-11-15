---
title: A check.sh never runs specs from the slow tier
when: design
tags: [check-sh, slow, speed]
check: Does any check.sh line run a spec listed in `tests/slow.tsv`, which the issue's `finish`, every `restack` and `done` will rerun?
---
An issue's check.sh runs at `finish`, at every `restack` and through the raft's check.sh at `done`, so a slow spec there is paid at every step of the raft, for every layer above it.

**Why:** c0248 design review 001 F13: its AC12 pulled about 2,850 s of slow-tier specs into check.sh; as layer 1 of a seven-layer raft it would have run at every restack.

**How to apply:** check only the fast specs that pin the change; the slow tier is the gate's (`z-nile/check.sh --slow`), run once in the implementation steps.

c0250 prep (2026-11-13): naming a slow spec by path in a fast run prints nothing, because `slow.keep` drops it; run it on purpose with `z-nile/check.sh --slow -- <paths>`.

c0302 design review 001 F6: when the slow specs are the files the issue changes, no gate runs them (z-design/guards-name-slow-tier-specs), so one check line may: run them once, never twice (its second run in the checkout repeated the first during execution), state the measured seconds in the design and beside the line, and say why this lesson's rule gives way.
