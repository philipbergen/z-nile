---
title: Re-read main's raft and issue state before launching and before done
when: both
tags: [tracker, origin-main, stale-state]
check: Did I run `git fetch` and read the raft's and its issues' current folders and design on origin/main (not the readied copy in my checkout or prompt) before I launched, and again before the Phase 5 merge?
---
A raft prompt is a snapshot of the designed tickets. If main stops the raft or re-preps its issues while you build, the whole branch lands on a prep nobody will merge.

**Why:** R0071 (c0191, "No leaked processes") was launched from a prompt written before main re-prepped c0191 "without spinner specs" (#221). Main stopped R0071 and moved c0191 to R0079 while the branch was built, reviewed and gated (about a day of work). Phase 5's `git merge origin/main` was the first look at it: tracker paths conflicted and PR #215 was blocked. The plan was made from the board listing, without reading the designed issue and its newer commits on main.

**How to apply:** at launch, `git fetch`, then `git log origin/main -- <raft folder> <each issue folder>` and read each issue's design. Confirm the raft is still readied. Repeat the log check at every phase start (after the review, before Phase 5), not only at the merge. If a raft or issue changed, stop and tell the user before spending more.
