---
title: Every rule `new` enforces is also an audit error for items that arrive by merge
when: both
tags: [tracker, audit, merges]
check: For each rule `new issue` or `new raft` refuses to break (one project per raft, a member's type, a root's shape), does `./zn audit` report an item that breaks it, so that a merge or another engine's capture can't bring one in unseen? And does each audit error name the one command that clears it, proven by running that command on the audit's own fixture?
---
A creating command can enforce a rule only for the items it makes. Items also arrive by merge: from another terminal, another branch, or an older engine that never knew the rule. If audit doesn't check the same rule, a merged item that breaks it passes every gate, and the only safeguard is someone rereading `./zn list` after each merge.

**Why:** R0043 code review 006 F1. `new raft` refused a raft that spans two projects. Main's old engine made R0047 in `tracker/` for c0127, which c0114's branch had moved into `z-nile/.tracker/`. After the merge, `members R0047` listed it and `./zn audit` reported 0 errors.

**How to apply:** when a design adds a refusal to `new`, add the matching `audit` error, read from the documents both ways (the raft's `issues:` list and each issue's `raft:` field). Exempt any state the rule allows by decision, and say why. Pin it with a spec in a `.cache` fixture and a mutant.

R0050 code review 002 F1: c0116 added the `dead-raft` audit error (an issue naming a retired or missing raft), and its message named `recombine` and `unfold`, which both refused such a raft: the error pointed at no way out. An audit error names the one command that clears the state it reports, and a spec runs that command on the audit's own fixture and sees the audit come back clean.
