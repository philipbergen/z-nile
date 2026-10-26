---
title: A fix to one line of a check runs the whole criterion it sits in
when: both
tags: [check-sh, finished, reachability]
check: Does the whole `check "ACn: …"` block a fixed line sits in pass on today's tree, run as `./zn check` runs it, so that the fixed line is reached at all?
---
A criterion is a script: an earlier statement that fails stops it before a later line runs. Fixing one line and testing that line alone says nothing about whether the check can ever fail on it.

**Why:** c0137 design review 002 F1: c0067 AC10's banned-word grep was fixed and tested line by line, but on main AC10 stopped earlier on statements naming skills c0115 had renamed, so the fixed grep never ran.

**How to apply:** after fixing a line, run its whole criterion from the check's home and expect it green; add a spec case that extracts and runs the whole criterion, with a mutant that breaks an earlier statement.
