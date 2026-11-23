---
title: An exception added to a guard states and tests everything it refuses
when: both
tags: [guards, publish, exceptions]
check: When a guard gains an exception, is the exception written as an exact list of what may change and under which conditions, reachable from one caller, with a test for each thing it must still refuse?
from: answers review of c0435, 2026-11-22 (#757)
---
An exception is reviewed for what it allows; the danger is everything near that.

**Why:** raising an easy ticket needed a new exception in the rule that guards what may be published to main. The reviewer read it line by line and found it could only raise, but no test covered any refusal (a lowered level, another ticket, a body edit), and it did not check the raft was the kind it was written for.

**How to apply:** one caller, exact fields, exact transitions; a refusal test per field and per neighbour case; the guard's own list names the exception and why.
