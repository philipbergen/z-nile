---
title: A rule handed to another raft is run against that raft's specs
when: design
tags: [rafts, conflicts, specs]
check: When this raft hands another prepared raft a rule ("whoever lands second does X"), has X been checked against that raft's sequestered and promoted specs, and do both rafts' specs pass with both changes in, whichever lands second?
---
A rule that looks easy from this raft's side can be impossible from the other's: the other raft's sequestered specs pin what it builds, and its executor may not edit them, so a rule that breaks one of them stops that raft.

**Why:** R0047 design review 005 F1: R0047 told R0039 to write a `start-<pid>` file beside its launcher's record, but R0039's sequestered `launcher-lock.spec` expects the lock to list exactly `pid-<launcher>`, so whichever raft landed second had to turn one of the two rafts' specs red. The user chose to put the id inside the record instead. f0158 design review 002 F2: f0126's prototype PICK rectangle, added to f0158's clearance spec, failed on seven screens that f0158's own prototype never drew.

**How to apply:** read the other raft's acceptance specs for every file, name or output your rule touches, and pick a rule they already allow; if none exists, put the choice to the user before either raft is readied.
