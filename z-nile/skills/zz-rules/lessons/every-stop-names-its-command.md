---
title: Every stop names the one command that clears it, and a case runs it
when: build
tags: [dispatch, stops]
check: After this stop, which command resumes the run, does the stop's message name it, and does a case run it?
---
A stop that holds until a human acts is a trap when the documented command (`vet`) leaves it in place and the one that clears it (`retry`) is named nowhere.

**Why:** R0052 code review 009 F2: the docs said to run `./zn dispatch vet` after an exit 5; the rerun after `vet` still stopped, and only `retry` cleared it.

**How to apply:** write the clearing command into the stop's message and the docs, and add a case that runs the sequence and checks the outcome changed.
