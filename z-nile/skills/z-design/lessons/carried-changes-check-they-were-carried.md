---
title: A check for a change that must be carried fails when it was published instead
when: design
tags: [checks, carried, publish, check-sh]
check: For each tracker edit the design says lands carried in the branch (not published to main first), does its check fail when it was published instead, although after a sync the tree looks the same either way? And does a judgement the carried command made on this tree (no dependents, no holder) get re-judged against `origin/main` when the branch lands?
---
A carried edit (`--carry`) and a published one leave the same document in the tree once the branch has synced or restacked onto `origin/main`, so a check that reads only the tree passes for both. The difference lives in history: a published edit leaves its own tracker commit for good.

**Why:** c0278 design review 001 F5: AC11 checked that c0268 was closed in the branch, and its Rules row said it killed "the executor publishes the close instead of carrying it"; after any sync it could not fail. And the carried close judged "nothing depends on c0268" on the branch's tree, while a capture could land a dependency on main after it.

**How to apply:** fail the check when HEAD's history of the document holds the published command's commit subject, and re-judge the carried command's conditions against `origin/main` (which `done` fetches before it runs the checks), so the check stays true when rerun from `done/`.
