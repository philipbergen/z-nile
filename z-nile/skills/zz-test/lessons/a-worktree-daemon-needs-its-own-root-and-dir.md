---
title: A daemon built in a worktree needs its own root and state folder
when: both
tags: [live, daemon, worktree, safety]
check: Before any build or start of the live daemon from a worktree or a spec, are ZN_LIVE_ROOT (the worktree) and ZN_LIVE_DIR (a throwaway folder under its .cache) both set?
---
Without them the build replaces the binary of the owner's running daemon, which exits when its binary changes, and the run writes into the real state.

**Why:** 2026-11-21, twice: a builder's spec wrote worker records into the real live state, and a builder's build from a worktree stopped the owner's daemon and the app with it.

**How to apply:** live specs set both through the shared helper; a brief for any builder near the live layer states it; never run ./zn live build bare from a worktree.
