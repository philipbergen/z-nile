---
title: A row a member writes in a PR has a path to main in every flow that writes it
when: design
tags: [provenance, publish, auto-merge, record]
check: For each record row, which command publishes it when the PR that carried it has already merged, and does the publish validator accept exactly that row?
---
A record row written into a branch reaches main only if the branch merges after the human acts. With auto-merge of prep PRs the branch merges first, and a later `approve --publish` that publishes one file leaves the row stranded.

**Why:** R0099 design review 001 F1: c0283's `approved` row lives in the local `tracker: approve` commit, but a dispatched prep PR merges before any human approves and `approve --publish` publishes `approval.md` alone, so `who` and the board show no approver.

**How to apply:** list each row event with the command that writes it and the command that publishes it after an early merge; a published row needs a validator branch tied to the file the same commit publishes (same human, same hash).

**Note (d0415 design review 001 F1):** a spend row the dispatcher could not record is kept pending in the state folder of the run that made it. A review its author started (a nested run) has a state folder of its own, `<step>-<mode>-<id>-<n>`, that `dispatch status <id>` and the next run's `flush` never read, so its row has no path to a ledger. For each place a row is kept for later, name the command that reads that place and the one that writes the row out, for the nested case too.
