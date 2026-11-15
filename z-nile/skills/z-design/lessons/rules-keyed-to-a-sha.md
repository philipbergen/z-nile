---
title: A rule keyed to a commit sha names who rewrites it and the way back
when: design
tags: [git, sha, rebase, review]
check: For every rule that names a commit (a review's or trace's `Commit:`), which commands rewrite that sha (restack, re-finish, a rebase onto a moved main), how often does that happen in this repository, and what way back do the existing tools allow (one-round refusals, never-edit rules)? Would an identity that survives a clean rebase (a patch id stamped by the tool) serve better?
---
A sha changes on every rebase, and in a repository where main moves with every tracker commit, a restack precedes nearly every landing. A rule that requires the reviewed sha to equal the current one turns each restack into new paperwork, and the one-round and never-edit rules then leave no allowed way back.

**Why:** c0248 design review 001 F4: the first design made every restack invalidate every layer review above it; a second review was refused as a second round, editing a review is forbidden, and the prototype's fixtures had to overwrite review-001.md to get round it.

**How to apply:** list the commands that rewrite the sha and their frequency in the Design; key the rule on what a clean rebase keeps (`git patch-id --stable`, stamped by the tool at review time), and keep the sha only as the first test.
