---
title: Seed landed items as main has them
when: design
tags: [fixtures, specs, mutants]
check: Does each fixture item in `done/` (or any later state) carry the front matter real items in that state have on `origin/main` (a landed raft member keeps its raft's claim stamp `status: active-…`), checked against a few real items, so that a rule that tests the folder and not the stamp is pinned?
---
A fixture that gives a landed member `status: done` lets two tests (the item's folder and its status stamp) stand in for each other: a mutant that drops the folder test survives, because the stamp test excludes the member anyway. On `origin/main` a landed member keeps the raft's claim stamp, so only the folder test keeps it out.

**Why:** c0250's prep (mutant re-run, 2026-11-13): dropping `mstate == "active"` from `block`'s member test survived. The fixture seeded the done members with `status: done`, while c0279 in `done/` has `status: active-quiet-copper-falcon`, as its raft R0089 has: 86 of the 136 issue documents in `done/` folders on main (2026-11-13) carry an `active-…` stamp.

**How to apply:** before seeding an item in a state, read two or three real items in that state (`git show origin/main:<path>`) and copy their front-matter shape; then name, for each rule, which field the fixture makes redundant.
