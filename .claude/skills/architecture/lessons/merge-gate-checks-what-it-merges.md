---
title: A merge gate checks what it merges and pins the commit it checked
when: design
tags: [security, merge, github]
check: Does the gate judge the PR's own commits (its head fetched and pinned, judged by the shared tracker-state function from the merge base), never a host's summary of them (gh's `files` hides a rename's source and stops at 100 files), and can the head change between the check and the merge?
---
A gate that merges on "green, mergeable, not a draft" merges whatever the branch holds: code in a prep PR, or a commit pushed after the check. Read the PR's changed files and its head commit, allow only what that kind of PR may carry, and merge pinned to that head (`gh pr merge --match-head-commit <sha>`), so a push since the check voids the merge.

**Why:** c0117 design review 002 F6: the dispatcher's prep gate would have merged a prep PR carrying code, with the user's credential, once CI was green, and nothing pinned the head between the check and the merge.

**How to apply:** fetch `refs/pull/<n>/head` into a private ref and refuse unless it equals `headRefOid`; judge `merge-base(main, head)..head` with the one tracker-state function plus a per-gate allow-list (prep: the issue's own folder and skill lessons; rafting: its own items' files); merge with `--match-head-commit`; spec a PR that carries code, one that renames code into the item, one with a stale head, and the pinned merge. (c0117 design review 003 F5, F11: this lesson first said to read gh's `files`, which is a fifth definition of tracker state.)
