---
title: A new front-matter line the tool writes is checked against every hash and guard that reads front matter
when: design
tags: [front-matter, hashes, records]
check: When the design makes a command write a new front-matter line into a document, which records hash that document (a raft's `grouped:` design record, an approval's contract, a capture's text), which guards compare it (publish's status-only rule), and does each one skip or accept the line as the design intends?
---
A front-matter line written by a command changes the document's text. Every record that hashes the document then sees a change nobody designed. A grouped member reads as redesigned, or an approval's contract changes. Every guard that compares the document before and after (a "status only" publish rule) also sees an extra line it refuses.

**Why:** c0306 prep, round 3 (2026-11-14). The claim's new `reviews: judged` line changed a grouped member's design record (`raftplan.designHash` skipped only `status:` and `raft:`). So `c0116/claims :: a member claimed after the carried move…` read "changed since grouped" instead of "preparing". The design had covered only `publish.luau`'s status-only comparison.

**How to apply:** list every reader of front matter that hashes or compares a whole document (`grep` for `designHash`, `contract`, `readFront` and the publish rules). Say in the Design whether each one skips the new line or includes it, and pin each answer with a case.

**Also:** c0288 design review 001 F3: the same holds for a change to another item's specs. `approval.collect` hashes every `*.spec.luau` under its `acceptance/`, and `raftplan.isDesignFile` counts `acceptance/` in a grouped record. An edit there voids both, and only the human re-approves.

**Also:** f0399 design review 001 F4 (2026-11-16): a line `ready` writes survives `stop`, and a promoted round-trip spec (`c0068/stop.spec`, every seeded document byte for byte but its status line) turns red. Search for whole-document comparisons across the command pair that writes and undoes the line. f0399 dropped the line for a trailer in the ready commit.
