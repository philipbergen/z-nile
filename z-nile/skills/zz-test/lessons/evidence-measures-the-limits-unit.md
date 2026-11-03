---
title: Evidence for a limit stop measures the limit's own unit
when: build
tags: [runner, limits, exit-codes]
check: Does the evidence for this exit code measure the same unit as the limit (per process vs summed over children), and does a case cover the most common other cause that has the same status (exit 1)?
---
A status chosen from summed child CPU (`times`) cannot tell one process hitting a per-process `ulimit -t` from several processes together using as much.

**Why:** R0071 code review 001 F1: a parallel command whose children used half the limit each and then failed with `exit 1` was reported as exit 125, "stopped at the CPU limit". The spec's parallel case used `exit 3`.

**How to apply:** either collect per-process evidence, or state in the docs that the code is a strong hint, and test the common status (1) with the same shape.
