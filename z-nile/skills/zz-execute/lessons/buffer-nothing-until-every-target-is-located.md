---
title: A write to several targets buffers nothing until every target is located, and each failure path takes back what it buffered
when: both
tags: [spend, buffer, retry, dispatcher]
check: After each early return in a write loop, what has already been appended to a buffer or ledger, and who folds it on the next attempt?
---
A loop that appends a line per target and then finds a target missing leaves the earlier lines behind; a retry appends them again and the next fold counts them twice.

**Why:** R0136 code review 001 F3: `publishMeasured` buffered the lowest member's line before it located the next member, so a raft row that waited for a member's folder put the raft's tokens on that member once per attempt.

**How to apply:** locate every target first; buffer only then; on every failure after the lines were appended, take back exactly those lines and keep what another writer appended since; add a case with a target that is missing, a retry and a count of the rows written.
