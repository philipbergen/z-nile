---
title: A merge gate checks what it merges and pins the commit it checked
when: design
tags: [security, merge, github]
check: Does the gate judge the PR's own commits (its head fetched and pinned, judged by the shared tracker-state function from the merge base), never a host's summary of them (gh's `files` hides a rename's source and stops at 100 files), and can the head change between the check and the merge?
---
A gate that merges on "green, mergeable, not a draft" merges whatever the branch holds: code in a prep PR, or a commit pushed after the check. Fetch the PR's head pinned to `headRefOid` and judge its commits from the merge base with the shared tracker-state function, allow only what that kind of PR may carry, and merge pinned to that head (`gh pr merge --match-head-commit <sha>`), so a push since the check voids the merge.

**Why:** c0117 design review 002 F6: the dispatcher's prep gate would have merged a prep PR carrying code, with the user's credential, once CI was green, and nothing pinned the head between the check and the merge.

**How to apply:** fetch `refs/pull/<n>/head` into a private ref and refuse unless it equals `headRefOid`; judge `merge-base(main, head)..head` with the one tracker-state function plus a per-gate allow-list (prep: the issue's own folder and skill lessons; rafting: its own items' files); merge with `--match-head-commit`; spec a PR that carries code, one that renames code into the item, one with a stale head, and the pinned merge. (c0117 design review 003 F5, F11: this lesson first said to read gh's `files`, which is a fifth definition of tracker state.)

Judge what the PR carries from its merge base, and what the merge does against today's main: every place an item rule reads (its lifecycle folder, its id in other roots) is read where the merged tree will put it, and a moved item refuses (R0052 code review 005 F1). Check: if main moved this item since the PR's base, which tree does the rule read?

A gate that merges unattended is held to the tracker's readers at every gate (the prep gate too, R0052 code review 007 F2), and compares what landed with what it judged by reading the merge commit from the system that made it, failing closed when it cannot (review 008 F1). Check: does every unattended merge path run the backstop, and does the post-merge check stop when it could not read the commit?

**Note (c0282 design review 001 F3):** a gate that allows a new kind of file judges it by shape against the item it belongs to, not by one field of it. The rafting gate took any appended `rafted` row, so a row on an issue the PR did not raft, one naming another raft and one with actor `unknown` reached `gh pr merge`. A record rides only the PR that moves the issue's own `raft:` line to the raft the rows name, with live actors and the exact detail grammar.
