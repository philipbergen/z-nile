---
title: A test that guards a limit fails fast when the limit is gone
when: both
tags: [specs, mutants, timeouts]
check: Does every client and read in a limit test have a deadline, so the test with the limit removed fails in seconds instead of hanging until the suite timeout?
from: f0437 review 002 (2026-11-21)
---
A limit test often streams until the server stops it. Without the limit nothing stops it, and the test hangs.

**Why:** f0437 review 002 (2026-11-21): `TestStreamCap` hung for the test timeout against its mutant.

**How to apply:** give each client and each read a deadline shorter than a second or two, and treat a deadline hit as the failure. Run the no-limit mutant and see it fail quickly.
