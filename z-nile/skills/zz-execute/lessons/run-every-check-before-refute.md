---
title: Every `./zn check <id>` runs after a gate change, before the answer to a review is committed
when: build
tags: [check, review-answer]
check: After the fix, did I run `./zn check <id>` (the promoted acceptance specs), not only the gate's affected specs?
---
A fix to shared tooling can turn a sequestered acceptance spec red while the gate stays green, because the gate does not run unpromoted acceptance specs.

**Why:** R0052 code review 007 F1: the merged-tree audit refused a raft document with no `slug:`, which AC10's sequestered `control-cli.spec` carries; the affected gate passed and `./zn check c0117` failed 10/11.

**How to apply:** run `./zn check <id>` for the raft's issues after every code fix to its engine, and put a red one to the user before editing the spec (a promoted spec is never edited without their approval).
