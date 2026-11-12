---
title: A gate that judges a document calls the checker that judges it
when: design
tags: [gates, audit, claim]
check: When a claim, a land or a gate decides whether a document is acceptable and a checker already judges the same document, does the gate call that checker (with the same inputs), or a lighter copy of its rules that can accept what the checker refuses?
---
Two judges of one document drift: the lighter one (headings present, a line of the right shape) admits records the full check refuses, and the later stage then meets work that should have been stopped at the gate.

**Why:** c0260 design reviews 006 F4, 007 F2 and 008 F1: the claim tested only that five headings existed, then that they were non-empty and of their kind, and still accepted a Confirmation that was no confirmation, a Q1 without its fields and a record never reviewed, all of which `capturecheck.check` refused.

**How to apply:** have the gate call the checker with the inputs it needs (here the raw reviews read from `origin/main`), and add a case where each thing the checker refuses is refused at the gate too, beside one where an accepted record passes.
