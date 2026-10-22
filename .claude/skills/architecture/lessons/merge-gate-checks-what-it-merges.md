---
title: A merge gate checks what it merges and pins the commit it checked
when: design
tags: [security, merge, github]
check: Which facts about the PR's contents does the gate read (its files, its head), and can the head change between the check and the merge?
---
A gate that merges on "green, mergeable, not a draft" merges whatever the branch holds: code in a prep PR, or a commit pushed after the check. Read the PR's changed files and its head commit, allow only what that kind of PR may carry, and merge pinned to that head (`gh pr merge --match-head-commit <sha>`), so a push since the check voids the merge.

**Why:** c0117 design review 002 F6: the dispatcher's prep gate would have merged a prep PR carrying code, with the user's credential, once CI was green, and nothing pinned the head between the check and the merge.

**How to apply:** `headRefOid` and `files` in the PR facts; a per-gate allow-list (prep: the issue's own folder and skill lessons; rafting: tracker documents); `--match-head-commit`; spec a PR that carries code waiting at the gate, and the pinned merge.
