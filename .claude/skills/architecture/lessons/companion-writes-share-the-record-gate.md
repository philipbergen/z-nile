---
title: A write that belongs with a record goes under the record's condition
when: both
tags: [records, gates, locks]
check: For each value written to go with a record (an id, a checksum, a timestamp), is it written only where and when the record is written, under the same gate, ideally in the same file?
---
A companion value written as its own file can escape the condition that guards the record: the record is skipped (another namespace, a disabled feature) while the companion is still written, and a reader pairs it with the wrong thing.

**Why:** R0047 design review 005 F3: under R0039's bwrap jail, `fence.recordsPid` skips a worker's `pid-<n>` because its pid belongs to another namespace; a separate `start-<namespace pid>` written ahead of that gate could match and overwrite the top's or the launcher's id on the host, letting a second run take over a live lock. Putting the id in the record's content puts it under the gate by construction.

**How to apply:** store the companion inside the record (one file, written whole), or write it in the same branch as the record and pin that with a case where the record is skipped.
