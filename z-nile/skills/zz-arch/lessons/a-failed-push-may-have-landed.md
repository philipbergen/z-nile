---
title: A push that reported failure may have landed
when: both
tags: [push, retry, rollback, git]
check: After every push whose failure leads to a retry or a rollback, does the command re-read the remote first, and which branch handles "the remote now holds my commit"?
---
A push can reach the remote and still exit non-zero (the connection drops after the ref moved). A command that then rolls back, or tries again, undoes or repeats something that already happened.

**Why:** d0331 design review 001 F6: the first draft of done's retry read "origin's main is no longer the commit I merged onto" as "main moved, try again". A binding commit that had landed matched that test, so the next attempt would have merged a stack that was already merged and crashed moving folders already in `done/`, with the pull request bases put back. `cmd.start` already re-reads the remote for its own push; `cmd.done` did not.

**How to apply:** after a failed push, fetch and compare the remote ref with the commit that was pushed. Equal means success: skip the rollback and go on. Only then decide between a retry and a refusal. Give it a spec case with a `git` on `PATH` that performs the push and then exits 1.
