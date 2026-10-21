---
title: A spec runs a new or changed command only in a fixture copy, never in the real tree
when: both
tags: [specs, fixtures, repository-safety]
check: Does any sequestered case run, against the real checkout, a command this raft adds or changes (a dry-run flag, a new mode, a new forwarder) whose wrong implementation would write the checkout or start a gate?
---
A case that runs a new `--plan` or dry-run flag in the real checkout trusts the code under test to write nothing. If the flag is wrong, a sequestered spec runs the real gate from inside a spec. It writes build output and sourcemaps in the checkout, unjailed on Linux and in CI's dispatch step. A separate fixture case that kills the wrong implementation doesn't help, because spec order guarantees nothing.

**Why:** c0120 design review 001 F2. gate-homes ran `z-nile/check.sh --plan` (and `pickman/check.sh --plan`) in the real checkout, and layout ran both forwarders with `--plan` there.

**How to apply:** build a copy of what the command reads (`engine.copy`, plus the registry and folders it needs) under `.cache/<name>`, run it there, and assert that nothing it would write appeared in the copy. Pin the real tree's files by reading them (their text, their registry), never by running the new command on them.
