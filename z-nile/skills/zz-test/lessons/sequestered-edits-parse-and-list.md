---
title: After any edit to a sequestered check.sh, it parses and lists before the prep commit
when: design
tags: [check.sh, sequestration, prep]
check: Does the edited check.sh still pass `bash -n`, and does `AC_LIST=1 bash check.sh` end "criteria listed (none run)", with each label matching the document's criterion?
---
A sequestered check.sh can only be fixed in the prep: once execution starts, an edit is a sequestration violation. An answer to a review that rewrites its criteria with a scripted edit can leave a fragment that breaks the whole file, and only c0114's promoted `classified.spec` (which lists every unfinished check.sh) would catch it, in the gate.

**Why:** c0139 design review 002 F1: the round-001 answer left a fragment of the old AC3 after AC4, so `bash -n` failed, `AC_LIST=1` never reached its summary, and `finish` never ran.

**How to apply:** after every check.sh edit in a prep, run `bash -n`, `AC_LIST=1 bash check.sh` from the item's home, and c0114's `classified.spec`; paste the outputs in the Verification log.
