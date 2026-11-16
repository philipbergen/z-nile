---
title: A decision to run less is made over exactly the inputs of the action it narrows
when: design
tags: [gate, selection, hooks]
check: When a design narrows an action (a scoped gate, a smaller selection, a skipped stage), is the narrowing decided over exactly the input set the full action would use, read by the same function and base (including committed and untracked changes and the files the caller usually filters out), and does a case exercise a change the caller's own filter drops?
---
A narrowing computed from a filtered or partial view of the inputs can run less than the action it replaces. The hook that decides "only pickman" must see what the gate sees, not what the hook happened to pass on.

**Why:** c0239 design review 002 F1: the stop hook handed `scope` only its filtered, uncommitted paths under `src/`, `tests/`, `z-nile/` and the project homes, so a change to the root `scripts/`, `zn` or a root config, or a committed change on the branch, never reached it, while the gate's `--affected` selects from the whole branch. The fix: `scope` takes no paths and reads the gate's own change set.

**How to apply:** name the input set of the full action, make the narrowing read that set through the same function, and add a case whose change the caller's filter would drop.
