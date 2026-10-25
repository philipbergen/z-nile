---
title: Every hand-merged hunk has a running spec
when: build
tags: [merge, specs, review]
check: For each hunk you merged by hand (the prototype against work that landed after the prep), which running spec fails if that hunk is wrong?
---
A prototype written in prep is proven against the tree of its day. When another raft lands on the same files before execution, the executor merges the two by hand, and the merged lines belong to neither raft's specs: the prep's specs know only the prototype, the other raft's often only pin source text. A fake engine built from the place file also misses anything made at run time, so a merged path can sit untested while the gate is green.

**Why:** R0034 review 001 F1. R0011 (hiscores) landed after R0034's prep and added a rank line and a `Rank` listener to `FlowView`, the file f0065 rewrote. The hand merge was right, but no spec ran FlowView with both the rank and the new prompt: f0065's client spec boots a place with no `Rank` remote (the server makes it), and f0026 checks only text. Keying `Flow.follow` on the wrong field, or drawing the rank into the prompt's label, passed the whole gate.

**How to apply:** after a conflicted `git apply --3way` or merge, list each hand-resolved hunk and name the running spec that would fail on a plausible wrong merge. Where there is none, write an executor spec that runs the merged code (giving the fake what exists only at run time), and run one wrong merge against it to see it fail.
