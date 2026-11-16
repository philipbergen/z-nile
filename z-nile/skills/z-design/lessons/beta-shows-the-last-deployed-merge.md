---
title: Beta shows the last ready pull request's merge with main, not main
when: design
tags: [deploy, publish, beta, observed]
check: When the design changes what Beta publishes (a place, a start place, a build), does it say what Beta shows between the raft's pull request leaving draft and its merge, when another ready pull request's deploy (main without the change) can publish the old state again, and are the Observed steps placed after the merge with a deploy since?
---
The Beta deploy runs for every ready pull request and publishes `refs/pull/<n>/merge`, the pull request merged with `main` at that moment, not `main` and not the branch's head. So a change to what Beta publishes appears when its own pull request leaves draft, and disappears again whenever another ready pull request deploys before the merge; after the merge, every deploy carries it.

**Why:** f0209's prep (2026-11-15): making the portal the start place looked like a merge-time switch, but the deploy log of #514 (`git checkout --progress --force refs/remotes/pull/514/merge`, "HEAD is now at be045c7 Merge 2b9a55c4… into af2c07eb…") showed Beta flips between the portal and the lobby while f0209's pull request is ready and others deploy. A rollback, likewise, goes live from its own ready pull request before it merges.

**How to apply:** read a recent deploy run's checkout step (`gh run view <id> --log`) rather than assuming; state the window in the design (and put an accepted flip to the user as a Guess); write Observed steps that start "after the merge and a deploy since", naming the log line that proves which build went out.
