---
title: A handler that starts to yield announces what it made
when: design
tags: [adapters, ordering, in-flight]
check: When a design turns an engine-event handler from one that finishes at once into one that yields (a Ready that now waits for a store), who else handles that event, in landed and in-flight work, and expects its effect to exist by the next resume (`task.defer`)? Does the handler give them a "made" signal instead?
---
A handler that waits moves its effect later than the code around it assumed; code that found the effect with a deferred look then finds nothing.

**Why:** f0148 design review 001 F3: Sessions' Ready handler started to wait for the stored start; f0145's in-flight `Continues` finds "the session made on this Ready" with `task.defer`, so a late claim would lose a paying player's continue offer and leave a refused run running.

**How to apply:** list every handler of the event (grep the landed code and every prep worktree in flight), add a signal fired when the effect exists (`Sessions.made(fn)`), pin it with a case, and tell the in-flight preps to use it.
