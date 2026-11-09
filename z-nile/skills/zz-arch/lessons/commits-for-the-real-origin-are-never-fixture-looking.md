---
title: A commit made for the real origin is never authored as a fixture
when: both
tags: [identity, tripwire, refs]
check: Does any commit this change writes outside a fixture use an `@example.invalid` identity (a `-c user.email=…` or a made-up author), and can a ref to it appear in the shared ref store (a pushed branch's remote-tracking ref, a fetched `refs/zn/*` ref) while a gate or spec run is going?
---
The spec runner's tripwire (`z-nile/tests/lib/fence.luau`, `FIXTURE_EMAIL`) fails a run on any new ref whose tip is authored `@example.invalid`, and every worktree shares the ref store with the main checkout. A commit a command makes for the real origin must carry the checkout's own identity (a fixture's own identity is an `@example.invalid` one, so a fixture write that leaks is still caught).

**Why:** c0265 design review 019 F1: the heartbeat's beat commit was authored `zn-beat@example.invalid`; each beat wrote `refs/remotes/origin/hb/<stamp>` and `refs/zn/hb-seen/<stamp>`, and the next gate run in any worktree failed with "refs written by a fixture appeared". The skills told every agent to keep `beat --watch` running, so every gate would have failed whenever a beat landed. The tempting fix, exempting the namespace in the tripwire, would open the very place a leaking fixture beat writes.

**How to apply:** author such commits with no `-c user.*` override (git then says so when there is no identity; never fall back to a fixture-looking one), pin the author in a spec (it equals the checkout's `git config user.email`), and name the tripwire's rule in the Design's guards.

**Note** (c0265 design review 021 F1): a rule that dates an event by "the commit that added X to main" reads `git log --first-parent`; on a merge commit the default history simplification follows the PR branch and returns the branch commit's time, before the merge. Check: what does the read return when the PR lands by a merge commit, a squash, a rebase, and after a revert and a re-land?
