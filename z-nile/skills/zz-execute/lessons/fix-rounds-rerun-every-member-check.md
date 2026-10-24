---
title: A fix round reruns every member's check.sh
when: build
tags: [review, checks, fixes]
check: Did each member's `./zn check` (and the raft's) pass after the last fix commit, not only the specs beside the edit?
---
A fix can break a criterion that only the item's own unpromoted specs see, while the full gate stays green.

**Why:** R0043 code review 002 F1: review-001's F2 doc fix put an old path into the testing skill. c0114's `docs.spec` forbids that path, but it isn't promoted yet, so only `check.sh` saw it. The author reran only the two specs beside the edit. The reviewer's own Recommendation had proposed the bad text.

**How to apply:** after every fix commit, before the refute, run each member's `check.sh` and the raft's. Treat a reviewer's proposed wording as input that must pass the same checks.
