---
title: A raft that departs from a member's Implementation step lists each override with its layer and a pushed ref
when: design
tags: [raft, executor, overrides, prototype]
check: Does each raft-level departure from a member's Implementation steps name the layer that applies it and a pushed ref holding the resolved code?
---
Executors follow the member documents and the raft's Order; an override that sits in an experiment paragraph, with its code on an unpushed local branch, is lost.

**Why:** R0099 design review 003 F1: c0284's `git apply prototype.patch` fails one hunk against c0280's final `who.luau`, and the streamed read lived only on local stack commits.

**How to apply:** one list in the Whole-raft design, one line per layer; push the scratch stack as a prototype ref; record the departures in the member's Verification log, never in its contract text.
