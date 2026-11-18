---
title: Before restacking an unfinished layer, its tip commit is not named like the finish commit
when: build
tags: [restack, layers, commit]
check: Is this layer unfinished and does its tip commit's subject start `<issue>: ` (as Phase 2's `./zn commit -m "<issue>: <what>"` suggests)? Then commit the next change with an `R<id>: ` subject, or restack replays that tip commit alone onto main?
---
`./zn restack` decides what to replay with `stack.rebaseUpstream` (`z-nile/engine/stack.luau`): a tip commit whose subject starts `<issue>: ` and whose parent is not in the layer below is read as the layer's finish commit, so only that one commit is rebased onto the new base. Before `./zn finish`, the layer's commits are the ones Phase 2 makes with `./zn commit -m "<issue>: <what>"`, so the tip of an unfinished layer looks exactly like a finish commit.

**Why:** R0131, 2026-11-17: `./zn finish d0297` refused (`not based on the layer below: ./zn restack R0131`) after main moved; `./zn restack R0131` then replayed only the tip, `d0297: verification log`, onto main, without the layer's earlier commits, and stopped on a conflict in the issue document (`Rebasing (1/1)`, `restack stopped at R0131/1/d0297: conflict`). It aborted cleanly, so nothing was lost.

**How to apply:** on a layer that is not finished yet, make the commit before a restack (or the last commit before `./zn finish`) with an `R<id>: ` subject, for example the raft's harvest or a note, so `rebaseUpstream` walks back to the `tracker: start <R-id>` commit and replays the whole layer. If the tip already has an `<issue>: ` subject and restack stops this way, `git status` shows the rebase was aborted; add an `R<id>: ` commit on top and restack again. The rule in `rebaseUpstream` is the engine's to fix (a finish commit is the only commit after the start mark); until then this is the workaround.
