---
title: Seed every case the code enumerates
when: both
tags: [fixtures, coverage]
check: Does the fixture seed every value of each set the code walks (every state folder, kind, mode or stream), and every combination when it walks two sets at once (kinds × states), so that dropping one turns a spec red? And for an adapter walked through states: which input combinations does the real producer hand it, and is each one in the case? And for a loopback standing in for a documented HTTP operation: does the fake return every status in that operation's response table, in a case the client has to accept, so that treating one listed status as a hard failure turns the case red? And when the design says a write leaves an entry, does the next read of that key return the body just written, so that answering a different status keeps the spec from going green?
---
When code iterates a fixed set (the backlog, `active/` and `done/` folders; issues and rafts; stdout and stderr), the spec fixture must hold at least one case of each value. A fixture that covers only some of them lets an implementation silently skip the rest.

**Why:** R0040 design review 1 (F1): `load` walks the backlog, `active/` and `done/`, but the CLI fixture seeded nothing under `active/`. Dropping `active/` still passed, which is exactly where a raft sits while its own checks run.

R0040 design review 2 (F2) found the same gap one level down: after `active/` was added, the fixture still covered only 3 of the 6 kind × state folders, so a reader that skipped `rafts/done` (where every finished raft's ledger lives) passed.

c0120 code review 002 F2: the fence strips ten overrides, and the cases seeded only `GIT_DIR`. A fix that stripped `GIT_DIR` alone before the read passed them; `GIT_COMMON_DIR` at another repository then escaped.

**How to apply:** for each loop over a fixed list in the Design, name the fixture entry that covers each element, and add a Rules row whose mutant drops one element. For nested loops, cover the cross product, not each list once.

c0120 code review 011 F2: a user decision exempted named branches from c0120's freeze, and `./zn busy` walks branches and then worktrees. The fixture seeded the exemption for branches only, so dropping it from the worktree loop (a worktree on an approved branch) left freeze.spec green, and nothing pinned a detached worktree or a look-alike name. When a decision covers two loops, seed the exemption in each: does dropping it from each loop turn a case red? F3, the same round: the supersede rule searched every place an item had (any root, any state), and no fixture put the stack's text at a place other than the item's path before the move and on main, so a search only at those two paths passed.

R0050 code review 003 F3: `retired/` joined the audit scan's states, but `list` and the bare `status` mapped every path that is not `active/` or `done/` to `backlog`, so a retired raft showed as a live backlog raft no command takes. A new state seeds a case in every display that maps paths to states.

c0135 design review 002 F1: a generated-name rule (`-2`, `-3`, …) was seeded only with its base taken, so a one-step suffix passed every case. Seed it with its own first output already taken. Check: does any case start from a set where the rule's first candidate is itself taken?

f0109 design review 003 F1: the MazeView and radar cases walked lit × edible as (F,F), (F,T), (T,T), but the game's only flash is (lit, not edible), since the level clear zeroes the power timer; a MazeView lit only while edible (MM1) and a radar that never flashes (DM1) passed. Walk the states the real producer emits, not only the rule's table.

c0172 design review 003 F1: the lease fake answered a missing entry with 404 only, while Get Entry's response table also lists 204 for a deleted key. Treating 204 as a hard failure still passed, and the next merge would stop. A loopback for a documented operation returns every status that table lists, in a case the client accepts. Check: does treating one listed status as a hard failure turn that case red?

R0059 code review 001 F1: c0153's plain.spec seeded NaN and +inf but not -inf, and compared numbers, tables and booleans but never two strings, so a `check` that let -inf through and an `equalWithin` that never compared strings both passed. For each type and each sign an equality or refusal handles, seed one case.
