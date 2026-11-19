---
title: A new path to a guarded act runs the guard, and a new early step keeps later refusals' words
when: both
tags: [guards, refusals, commands, placement]
check: Which call sites now reach each guarded write (placed, in-process, retried), and does each one run the guard the skill states for it; and for each step this change runs before an existing refusal, does that refusal still fire for its input with its own words?
---
A command that gains a new way in (a placed run in another checkout beside the old in-process run, a retry, a new mode) keeps every guard the skills state for its write only if each path runs that guard. A step inserted ahead of an existing refusal (placement before the item lookup) answers first for inputs the refusal used to name, and its answer is then the wrong reason.

**Why:** R0130 code review 001 (c0369, 2026-11-18). F1: zz-rules says a worktree on no branch is refused before anything is recorded, but the no-branch check ran only when the run was placed (`ZN_APPROVE_IN` set); run inside a detached worktree that held a design of its own, the command acted in its own process, recorded `tracker: approve` on the detached HEAD and then failed every retry it named. F3: placement ran before `approve takes an issue (<id> is a raft)`, so `./zn approve R0130` was told there was nothing to approve. The prototype and four design rounds missed both; one probe in a fixture found the first.

**How to apply:** list the paths that reach the guarded act (grep the call that writes, and each branch that leads to it: placed, in-process, retried, no origin) and put the guard where every one of them passes, or one case per path; for a new early step, list the refusals it now runs ahead of and give the step the cheap check that keeps each one's words (an id shape, a flag), with a case that pins the old text.
