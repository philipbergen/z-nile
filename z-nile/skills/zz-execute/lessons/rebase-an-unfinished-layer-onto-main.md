---
title: An unfinished layer that merged main is rebased onto origin/main before finish
when: build
tags: [restack, layers, sync, finish]
check: Did `./zn sync` merge origin/main into this layer before its first finish? Then rebase the layer's own commits onto origin/main and publish them with a lease before `./zn finish`, since restack replays main's merged commits and stops?
---
`./zn sync` in a raft worktree merges `origin/main` into the layer. On a layer that is not finished yet, `./zn finish` then refuses (`not based on the layer below: ./zn restack <R-id>`), and `./zn restack` resets to the published layer and replays every commit after the layer's recorded base, the commits the merge brought from main included, so it stops on a conflict in one of them and aborts.

**Why:** R0130, 2026-11-18: main moved (d0413 fixed a red loop scan the build's `slow.tsv` change had selected), `./zn sync` merged it into `R0130/1/c0369`, `./zn finish c0369` refused, and `./zn restack R0130` stopped twice on `tracker: new d0415`, a main commit, and aborted cleanly.

**How to apply:** `git fetch origin main && git rebase origin/main` on the layer (a plain rebase replays only the commits not on main and drops the merge), check `git log origin/main..HEAD` holds only the layer's own commits, publish with `git push --force-with-lease=refs/heads/<layer>:<the published tip> origin HEAD:refs/heads/<layer>`, then `./zn finish`. Better still, while a layer is unfinished and needs main's change, rebase instead of `./zn sync`. Restack's base rule is the engine's to fix.
