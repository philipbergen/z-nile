---
title: A refute's "is now X" shows in the diff
when: build
tags: [refute, review, ledger]
check: For every "is now X" or "now says X" in my refute file, does `git diff` of the document it names show line X?
---
A refute line that says a table row or section was changed is read as fact. If only the Verification log changed, the document itself still says the old thing.

**Why:** R0088 code review 002 F2 (c0246): refute-001 said the Rules row N15 was now `run`; only the log said so, and the row, the Test plan and Touched modules were unchanged.

**How to apply:** after writing the refute, grep each document it says it changed for the new text.

**Note (R0117 code review 001 F1):** the same holds for a Verification log. f0208's log said a joint was "raised under R0117's `## Open to the human`", and the raft document had no `- F<n>:` bullet, which is the only thing `done`'s open-list check and the human read. Write the bullet in the same commit as the log line, and grep the raft document for it.
