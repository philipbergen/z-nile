---
title: A member's prep fix lands before the rafting that groups it
when: design
tags: [raft, grouped, prep]
check: Does this rafting branch change any member's design files (its document, check.sh, acceptance specs, reviews or harvest), which `new raft` and `fold` hash from origin/main, so that `ready` refuses the landed raft?
from: R0062 rafting, 2026-10-26
---
`new raft` records each prepared member's design hash from origin/main, not from the branch. A fix to a member made in the rafting branch (here c0141's uses-module.spec needle) lands with the raft, so origin/main's design then differs from the record and `./zn ready` refuses: "changed on origin/main since R0062 grouped it". `fold` can't re-record a member origin/main already lists in that raft, so the tool's way out is an unfold PR, then a fold PR.

**Why:** R0062 (2026-10-26): the needle fix rode in the rafting PR #164; `ready` refused; the record was refreshed to the landed hash and a second coherence review quoted it.

**How to apply:** land a member's fix as its own prep change before rafting it, or raft first and fix it afterwards with `fold` per rafted-member-changes-stay-in-the-raft.
