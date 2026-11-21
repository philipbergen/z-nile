---
title: A rule keyed to a commit sha names who rewrites it and the way back
when: design
tags: [git, sha, rebase, review]
check: For every rule that names a commit (a review's or trace's `Commit:`), which commands rewrite that sha (restack, re-finish, a rebase onto a moved main), how often does that happen in this repository, and what way back do the existing tools allow (one-round refusals, never-edit rules)? Would an identity that survives a clean rebase (a patch id stamped by the tool) serve better?
---
A sha changes on every rebase, and in a repository where main moves with every tracker commit, a restack precedes nearly every landing. A rule that requires the reviewed sha to equal the current one turns each restack into new paperwork, and the one-round and never-edit rules then leave no allowed way back.

**Why:** c0248 design review 001 F4: the first design made every restack invalidate every layer review above it; a second review was refused as a second round, editing a review is forbidden, and the prototype's fixtures had to overwrite review-001.md to get round it.

**How to apply:** list the commands that rewrite the sha and their frequency in the Design; key the rule on what a clean rebase keeps (`git patch-id --stable`, stamped by the tool at review time), and keep the sha only as the first test.

**Note (c0248 re-prep, design review 003 F1, 2026-11-19):** a rule that makes a record stale needs its filed way back in the same design. c0248's layer review went stale on any change of the layer's patch, and the dispatcher's one-round rule refused the next round, so a fixed layer could never be complete again. Ask: when a commit, fix or restack makes this record not current, which command makes a new current one, and does the one-round rule allow it?
