---
title: A row a member writes in a PR has a path to main in every flow that writes it
when: design
tags: [provenance, publish, auto-merge, record]
check: For each record row, which command publishes it when the PR that carried it has already merged, and does the publish validator accept exactly that row?
---
A record row written into a branch reaches main only if the branch merges after the human acts. With auto-merge of prep PRs the branch merges first, and a later `approve --publish` that publishes one file leaves the row stranded.

**Why:** R0099 design review 001 F1: c0283's `approved` row lives in the local `tracker: approve` commit, but a dispatched prep PR merges before any human approves and `approve --publish` publishes `approval.md` alone, so `who` and the board show no approver.

**How to apply:** list each row event with the command that writes it and the command that publishes it after an early merge; a published row needs a validator branch tied to the file the same commit publishes (same human, same hash).
